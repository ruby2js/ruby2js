// Ruby2JS-on-Rails Micro Framework - Cloudflare Workers Target
// Extends server module with Worker fetch handler pattern
// Includes Durable Objects support for Turbo Streams broadcasting

import {
  Router as RouterServer,
  Application as ApplicationServer,
  setNestedParam,
  createContext,
  createFlash,
  truncate,
  pluralize,
  dom_id,
  navigate,
  submitForm,
  formData,
  handleFormResult,
  setupFormHandlers,
  resolveContent
} from 'juntos/rails_server.js';

// Re-export everything from server module
export { createContext, createFlash, truncate, pluralize, dom_id, navigate, submitForm, formData, handleFormResult, setupFormHandlers };

// Cloudflare-specific turbo_stream_from - uses simple element for turbo_cable_simple.js
// This avoids Action Cable protocol and allows true Durable Object hibernation
// Usage in ERB: <%= turbo_stream_from "articles" %>
export function turbo_stream_from(streamName) {
  // Simple element that turbo_cable_simple.js will pick up and handle
  return `<turbo-stream-source stream="${streamName}"></turbo-stream-source>`;
}

// Router with Cloudflare-specific redirect handling
export class Router extends RouterServer {
  // Override redirect to use full URL (Cloudflare requires absolute URLs)
  static redirect(context, path) {
    const url = new URL(path, context.request.url);
    const headers = new Headers({ 'Location': url.href });

    // Add flash cookie if there are pending messages
    const flashCookie = context.flash.getResponseCookie();
    if (flashCookie) {
      headers.set('Set-Cookie', flashCookie);
    }

    return new Response(null, { status: 302, headers });
  }

  // Override parseBody to handle multipart/form-data
  static async parseBody(req) {
    const contentType = req.headers.get('content-type') || '';

    try {
      if (contentType.includes('application/json')) {
        return await req.json();
      } else if (contentType.includes('application/x-www-form-urlencoded')) {
        const formData = await req.formData();
        const params = {};
        for (const [key, value] of formData.entries()) {
          setNestedParam(params, key, value);
        }
        return params;
      } else if (contentType.includes('multipart/form-data')) {
        const formData = await req.formData();
        const params = {};
        for (const [key, value] of formData.entries()) {
          // Skip file uploads for now, just get string values
          if (typeof value === 'string') {
            setNestedParam(params, key, value);
          }
        }
        return params;
      }
    } catch (e) {
      console.warn('Failed to parse request body:', e.message);
    }

    return {};
  }

  // Override handleResult to use full URL for redirects
  static async handleResult(context, result, defaultRedirect) {
    if (result.turbo_stream) {
      // Turbo Stream response - return with proper content type
      console.log('  Rendering turbo_stream response');
      return this.turboStreamResponse(context, result.turbo_stream);
    } else if (result.redirect) {
      // Set flash notice if present in result
      if (result.notice) {
        context.flash.set('notice', result.notice);
      }
      if (result.alert) {
        context.flash.set('alert', result.alert);
      }
      console.log(`  Redirected to ${result.redirect}`);
      return this.redirect(context, result.redirect);
    } else if (result.render) {
      // Return 422 Unprocessable Entity so Turbo Drive renders the response
      console.log('  Re-rendering form (validation failed)');
      return await this.htmlResponse(context, result.render, 422);
    } else {
      return this.redirect(context, defaultRedirect);
    }
  }

  // Create Turbo Stream response with proper content type
  static turboStreamResponse(context, html) {
    const headers = { 'Content-Type': 'text/vnd.turbo-stream.html; charset=utf-8' };

    const flashCookie = context.flash.getResponseCookie();
    if (flashCookie) {
      headers['Set-Cookie'] = flashCookie;
    }

    return new Response(html, { status: 200, headers });
  }

  // Override htmlResponse to use the correct Application class
  // (Parent class references its own Application which doesn't have layoutFn set)
  static async htmlResponse(context, content, status = 200) {
    const html = await resolveContent(content);
    const fullHtml = Application.wrapInLayout(context, html);
    const headers = { 'Content-Type': 'text/html; charset=utf-8' };

    const flashCookie = context.flash.getResponseCookie();
    if (flashCookie) {
      headers['Set-Cookie'] = flashCookie;
    }

    return new Response(fullHtml, { status, headers });
  }
}

// Application with Cloudflare Worker pattern
export class Application extends ApplicationServer {
  static _initialized = false;

  // Initialize the database using the adapter
  // env contains the D1 binding (e.g., env.DB)
  // Note: Migrations are NOT run automatically - use 'juntos migrate' before deploying
  static async initDatabase(env) {
    if (this._initialized) return;

    // Import the adapter (selected at build time)
    const adapter = await import('juntos:active-record');
    this.activeRecordModule = adapter;

    // Initialize database connection with D1 binding
    await adapter.initDatabase({ binding: env.DB });

    this._initialized = true;
  }

  // Create the Worker fetch handler
  // Usage in worker entry point:
  //   import { Application, Router, TurboBroadcaster } from './lib/rails.js';
  //   export default Application.worker();
  //   export { TurboBroadcaster };
  static worker() {
    const app = this;
    return {
      async fetch(request, env, ctx) {
        try {
          // Store env for broadcasting
          app.env = env;

          // Initialize database on first request
          await app.initDatabase(env);

          const url = new URL(request.url);

          // Handle WebSocket connections via Durable Object
          if (url.pathname === '/cable') {
            if (env.TURBO_BROADCASTER) {
              const id = env.TURBO_BROADCASTER.idFromName('global');
              const broadcaster = env.TURBO_BROADCASTER.get(id);
              return broadcaster.fetch(request);
            }
            return new Response('Durable Object not configured', { status: 503 });
          }

          // Dispatch the request
          return await Router.dispatch(request);
        } catch (e) {
          console.error('Worker error:', e);
          return new Response(`<h1>500 Internal Server Error</h1><pre>${e.stack}</pre>`, {
            status: 500,
            headers: { 'Content-Type': 'text/html' }
          });
        }
      }
    };
  }
}

// Durable Object for Turbo Streams broadcasting
// Uses simple protocol (no Action Cable, no pings) for hibernation-friendly operation
// The Durable Object truly hibernates between broadcasts - no alarms wake it up
// Add to wrangler.toml:
//   [durable_objects]
//   bindings = [{ name = "TURBO_BROADCASTER", class_name = "TurboBroadcaster" }]
export class TurboBroadcaster {
  constructor(state, env) {
    this.state = state;
    this.env = env;
    // Map of stream name -> Set of WebSocket connections
    this.streams = new Map();
  }

  async fetch(request) {
    const url = new URL(request.url);

    // Handle WebSocket upgrade
    if (request.headers.get('Upgrade') === 'websocket') {
      const pair = new WebSocketPair();
      const [client, server] = Object.values(pair);

      // Accept the WebSocket with hibernation support
      // Cloudflare keeps the connection alive at the edge while DO sleeps
      this.state.acceptWebSocket(server);

      // Send simple welcome (no Action Cable protocol)
      server.send(JSON.stringify({ type: 'welcome' }));

      // No ping alarm needed - Cloudflare maintains the connection
      // The DO can truly hibernate until a broadcast or message arrives

      return new Response(null, { status: 101, webSocket: client });
    }

    // Handle broadcast POST from model callbacks
    if (request.method === 'POST' && url.pathname === '/broadcast') {
      const { stream, html } = await request.json();
      this.broadcastToStream(stream, html);
      return new Response('ok');
    }

    return new Response('Not found', { status: 404 });
  }

  // WebSocket message handler (with hibernation support)
  // Simple protocol: { type: 'subscribe'|'unsubscribe', stream: 'name' }
  async webSocketMessage(ws, message) {
    try {
      const msg = JSON.parse(message);

      switch (msg.type) {
        case 'subscribe':
          this.subscribe(ws, msg.stream);
          break;
        case 'unsubscribe':
          this.unsubscribe(ws, msg.stream);
          break;
      }
    } catch (e) {
      console.error('WebSocket message error:', e);
    }
  }

  // WebSocket close handler
  async webSocketClose(ws, code, reason, wasClean) {
    this.cleanup(ws);
  }

  // WebSocket error handler
  async webSocketError(ws, error) {
    console.error('WebSocket error:', error);
    this.cleanup(ws);
  }

  subscribe(ws, stream) {
    if (!this.streams.has(stream)) {
      this.streams.set(stream, new Set());
    }
    this.streams.get(stream).add(ws);

    // Store subscription in WebSocket attachment for cleanup
    const attachment = ws.deserializeAttachment() || { streams: [] };
    if (!attachment.streams.includes(stream)) {
      attachment.streams.push(stream);
    }
    ws.serializeAttachment(attachment);

    // Send confirmation
    try {
      ws.send(JSON.stringify({ type: 'subscribed', stream }));
    } catch (e) {
      // Ignore send errors
    }
  }

  unsubscribe(ws, stream) {
    const subscribers = this.streams.get(stream);
    if (subscribers) {
      subscribers.delete(ws);
      if (subscribers.size === 0) {
        this.streams.delete(stream);
      }
    }
  }

  cleanup(ws) {
    const attachment = ws.deserializeAttachment();
    if (attachment && attachment.streams) {
      for (const stream of attachment.streams) {
        this.unsubscribe(ws, stream);
      }
    }
  }

  broadcastToStream(stream, html) {
    const subscribers = this.streams.get(stream);
    if (!subscribers || subscribers.size === 0) {
      return;
    }

    // Simple message format: { stream, html }
    // The client's turbo_cable_simple.js knows how to handle this
    const message = JSON.stringify({ stream, html });

    for (const ws of subscribers) {
      try {
        ws.send(message);
      } catch (e) {
        this.cleanup(ws);
      }
    }
  }
}

// TurboBroadcast for Cloudflare - broadcasts via Durable Object
// Models call: BroadcastChannel.broadcast("channel", html)
export class TurboBroadcast {
  static env = null;

  static async broadcast(channel, html) {
    // Get env from Application
    const env = Application.env;
    if (!env || !env.TURBO_BROADCASTER) {
      console.warn('TurboBroadcast: Durable Object not configured');
      return;
    }

    try {
      const id = env.TURBO_BROADCASTER.idFromName('global');
      const broadcaster = env.TURBO_BROADCASTER.get(id);

      await broadcaster.fetch(new Request('https://internal/broadcast', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ stream: channel, html })
      }));
    } catch (e) {
      console.error('TurboBroadcast error:', e);
    }
  }
}

// Export BroadcastChannel as alias for model broadcast methods
export { TurboBroadcast as BroadcastChannel };

// Set on globalThis for instance methods in active_record_base.mjs
globalThis.TurboBroadcast = TurboBroadcast;
