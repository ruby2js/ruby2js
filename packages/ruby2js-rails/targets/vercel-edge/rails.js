// Ruby2JS-on-Rails Micro Framework - Vercel Edge Functions Target
// Extends server module with Vercel Edge handler pattern
// Note: Turbo Streams broadcasting is stubbed (Vercel Edge doesn't support persistent WebSockets)

import {
  Router as RouterServer,
  Application as ApplicationServer,
  extractNestedKey,
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
  resolveContent
} from 'ruby2js-rails/rails_server.js';

// Re-export everything from server module
export { createContext, createFlash, truncate, pluralize, dom_id, navigate, submitForm, formData, handleFormResult, setupFormHandlers, turbo_stream_from };

// Stubbed TurboBroadcast for Vercel Edge - no persistent WebSocket support
// Broadcasts are silently ignored since Vercel Edge Functions don't support WebSockets
// Consider using external pub/sub services (e.g., Pusher, Ably) for real-time features
export class TurboBroadcast {
  static broadcast(channel, html) {
    // No-op: Vercel Edge Functions don't support persistent WebSocket connections
    console.log(`TurboBroadcast (stubbed): would broadcast to ${channel}`);
  }

  static subscribe(channel) {
    console.log(`TurboBroadcast (stubbed): would subscribe to ${channel}`);
  }

  static unsubscribe(channel) {
    console.log(`TurboBroadcast (stubbed): would unsubscribe from ${channel}`);
  }
}

// Export BroadcastChannel as alias for model broadcast methods
export { TurboBroadcast as BroadcastChannel };

// Router with Vercel Edge-specific redirect handling
export class Router extends RouterServer {
  // Override redirect to use full URL (Edge Functions require absolute URLs)
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
          params[extractNestedKey(key)] = value;
        }
        return params;
      } else if (contentType.includes('multipart/form-data')) {
        const formData = await req.formData();
        const params = {};
        for (const [key, value] of formData.entries()) {
          // Skip file uploads for now, just get string values
          if (typeof value === 'string') {
            params[extractNestedKey(key)] = value;
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

// Application with Vercel Edge Function pattern
export class Application extends ApplicationServer {
  static _initialized = false;

  // Initialize the database using the adapter
  // Uses environment variables (Vercel convention)
  // Note: Migrations are NOT run automatically - use 'juntos migrate' before deploying
  static async initDatabase() {
    if (this._initialized) return;

    // Import the adapter (selected at build time)
    const adapter = await import('juntos:active-record');
    this.activeRecordModule = adapter;

    // Initialize database connection with environment variable
    // Vercel Edge supports process.env for environment variables
    await adapter.initDatabase({
      url: process.env.DATABASE_URL,
    });

    this._initialized = true;
  }

  // Create the Edge Function handler
  // Usage in api/[[...path]].js:
  //   import { Application, Router } from '../lib/rails.js';
  //   export default Application.handler();
  //   export const config = { runtime: 'edge' };
  static handler() {
    const app = this;
    return async function(request, context) {
      try {
        // Initialize database on first request
        await app.initDatabase();

        // Dispatch the request
        return await Router.dispatch(request);
      } catch (e) {
        console.error('Edge Function error:', e);
        return new Response(`<h1>500 Internal Server Error</h1><pre>${e.stack}</pre>`, {
          status: 500,
          headers: { 'Content-Type': 'text/html' }
        });
      }
    };
  }
}
