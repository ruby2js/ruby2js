// Ruby2JS-on-Rails Micro Framework - BEAM (QuickBEAM) Target
// Extends server module with QuickBEAM runtime pattern
// Uses BroadcastChannel (backed by OTP :pg) for Turbo Streams broadcasting

import {
  Router as RouterServer,
  Application as ApplicationServer,
  TurboBroadcast as TurboBroadcastServer,
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
  turbo_stream_from,
  resolveContent,
  stylesheetLinkTag,
  javascriptImportmapTags,
  getAssetPath
} from 'juntos/rails_server.js';

// Re-export everything from server module
export { createContext, createFlash, truncate, pluralize, dom_id, navigate, submitForm, formData, handleFormResult, setupFormHandlers, turbo_stream_from, stylesheetLinkTag, javascriptImportmapTags, getAssetPath };

// Helper: create a Response that works in QuickBEAM
// QuickBEAM's Response constructor requires Uint8Array body, not strings
function beamResponse(body, init) {
  const encoded = typeof body === 'string' ? new TextEncoder().encode(body)
    : body instanceof Uint8Array ? body
    : body == null ? null
    : new TextEncoder().encode(String(body));
  // QuickBEAM Response needs: (Uint8Array|null, {status, statusText, headers, url})
  const headers = init.headers instanceof Headers ? init.headers
    : new Headers(Object.entries(init.headers || {}));
  return new Response(encoded, {
    status: init.status || 200,
    statusText: init.statusText || 'OK',
    headers: headers,
    url: init.url || ''
  });
}

// Router with BEAM-specific overrides
export class Router extends RouterServer {
  // Override redirect to use full URL (like Cloudflare/Vercel targets)
  static redirect(context, path) {
    const url = new URL(path, context.request.url);
    const headers = new Headers({ 'Location': url.href });

    const flashCookie = context.flash.getResponseCookie();
    if (flashCookie) {
      headers.set('Set-Cookie', flashCookie);
    }

    return beamResponse(null, { status: 302, headers });
  }

  // Override parseBody to handle multipart/form-data via Fetch API
  static async parseBody(req) {
    const contentType = req.headers.get('content-type') || '';

    try {
      if (contentType.includes('application/json')) {
        return await req.json();
      } else if (contentType.includes('application/x-www-form-urlencoded')) {
        const text = await req.text();
        const params = {};
        const pairs = text.split('&');
        for (const pair of pairs) {
          const [key, value] = pair.split('=');
          if (key) {
            const decodedKey = decodeURIComponent(key.replace(/\+/g, ' '));
            const decodedValue = decodeURIComponent((value || '').replace(/\+/g, ' '));
            setNestedParam(params, decodedKey, decodedValue);
          }
        }
        return params;
      } else if (contentType.includes('multipart/form-data')) {
        const formData = await req.formData();
        const params = {};
        for (const [key, value] of formData.entries()) {
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
      console.log('  Rendering turbo_stream response');
      return this.turboStreamResponse(context, result.turbo_stream);
    } else if (result.redirect) {
      if (result.notice) {
        context.flash.set('notice', result.notice);
      }
      if (result.alert) {
        context.flash.set('alert', result.alert);
      }
      console.log(`  Redirected to ${result.redirect}`);
      return this.redirect(context, result.redirect);
    } else if (result.render) {
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

    return beamResponse(html, { status: 200, headers });
  }

  // Override htmlResponse to use the correct Application class
  static async htmlResponse(context, content, status = 200) {
    const html = await resolveContent(content);
    const fullHtml = Application.wrapInLayout(context, html);
    const headers = { 'Content-Type': 'text/html; charset=utf-8' };

    const flashCookie = context.flash.getResponseCookie();
    if (flashCookie) {
      headers['Set-Cookie'] = flashCookie;
    }

    return beamResponse(fullHtml, { status, headers });
  }
}

// TurboBroadcast for BEAM - bridges to Elixir for WebSocket broadcasting
// JS only sends; Elixir manages all WebSocket connections and subscriptions
export class TurboBroadcast {
  static broadcast(channel, html) {
    try {
      Beam.callSync('__broadcast', channel, html);
    } catch (e) {
      console.error('TurboBroadcast error:', e);
    }
  }
}

// Export BroadcastChannel as alias for model broadcast methods
export { TurboBroadcast as BroadcastChannel };

// Set on globalThis for instance methods in active_record_base.mjs
globalThis.TurboBroadcast = TurboBroadcast;

// Application with QuickBEAM runtime pattern
export class Application extends ApplicationServer {
  static _initialized = false;

  // Initialize the database using the adapter
  static async initDatabase(options = {}) {
    if (this._initialized) return;

    const adapter = await import('juntos:active-record');
    this.activeRecordModule = adapter;

    await adapter.initDatabase(options);

    this._initialized = true;
  }

  // Entry point called by the Elixir host
  // Returns a handler function that takes a Request and returns a Response
  static handler() {
    const app = this;
    return async function(request) {
      try {
        await app.initDatabase();
        return await Router.dispatch(request);
      } catch (e) {
        console.error('BEAM handler error:', e);
        return beamResponse(`<h1>500 Internal Server Error</h1><pre>${e.stack}</pre>`, {
          status: 500,
          headers: { 'Content-Type': 'text/html' }
        });
      }
    };
  }
}
