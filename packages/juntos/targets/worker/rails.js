// Ruby2JS-on-Rails Micro Framework - SharedWorker Target
// Application tier: runs Router, controllers, models, and views
// inside a SharedWorker, serving all browser tabs through MessagePort.
//
// Communicates with:
// - Main thread tabs via MessagePort (HTTP-like request/response)
// - Dedicated database Worker via postMessage (SQL queries)
// - All tabs via BroadcastChannel (Turbo Streams)

import {
  Router as RouterServer,
  Application as ApplicationServer,
  TurboBroadcast as TurboBroadcastServer,
  createContext,
  createFlash,
  truncate,
  pluralize,
  dom_id,
  resolveContent
} from 'juntos/rails_server.js';

import { setWorker } from 'juntos/adapters/active_record_worker.mjs';

// Re-export base helpers
export { createContext, createFlash, truncate, pluralize, dom_id };

// Router — uses the server Router's dispatch which returns Fetch API Responses
export class Router extends RouterServer {
  // Override parseBody to handle our message protocol
  // The body is already parsed by the client bridge before sending
  static async parseBody(req) {
    if (req._parsedBody) {
      return req._parsedBody;
    }

    const contentType = (req.headers && typeof req.headers.get === 'function')
      ? req.headers.get('content-type') || ''
      : (req.headers?.['content-type'] || '');

    if (contentType.includes('application/json') && req._bodyText) {
      try {
        return JSON.parse(req._bodyText);
      } catch {
        return {};
      }
    } else if (req._bodyText) {
      const params = {};
      const pairs = req._bodyText.split('&');
      for (const pair of pairs) {
        const [key, value] = pair.split('=');
        if (key) {
          const decodedKey = decodeURIComponent(key.replace(/\+/g, ' '));
          const decodedValue = decodeURIComponent((value || '').replace(/\+/g, ' '));
          const match = decodedKey.match(/^([^\[]+)\[([^\]]+)\]$/);
          if (match) {
            const [, model, field] = match;
            if (!params[model]) params[model] = {};
            params[model][field] = decodedValue;
          } else {
            params[decodedKey] = decodedValue;
          }
        }
      }
      return params;
    }

    return {};
  }
}

// Turbo Streams Broadcasting via BroadcastChannel API
// BroadcastChannel is available in SharedWorker context and reaches all tabs
export class TurboBroadcast {
  static channels = new Map();

  static getChannel(name) {
    if (!this.channels.has(name)) {
      const channel = new globalThis.BroadcastChannel(name);
      this.channels.set(name, channel);
    }
    return this.channels.get(name);
  }

  static broadcast(channelName, html) {
    console.debug(`  [Broadcast] ${channelName}:`, html.substring(0, 100) + (html.length > 100 ? '...' : ''));
    const channel = this.getChannel(channelName);
    channel.postMessage(html);
  }

  static subscribe(channelName, callback) {
    console.debug(`  [Subscribe] ${channelName}`);
    const channel = this.getChannel(channelName);
    channel.onmessage = (event) => {
      console.log(`  [Received] ${channelName}:`, event.data.substring(0, 100) + (event.data.length > 100 ? '...' : ''));
      if (callback) callback(event.data);
    };
    return '';
  }

  static unsubscribe(channelName) {
    const channel = this.channels.get(channelName);
    if (channel) {
      channel.close();
      this.channels.delete(channelName);
    }
  }
}

// Export BroadcastChannel alias for model broadcast methods
export { TurboBroadcast as BroadcastChannel };
globalThis.TurboBroadcast = TurboBroadcast;

// Helper for views to subscribe to turbo streams
export function turbo_stream_from(channelName) {
  TurboBroadcast.subscribe(channelName);
  return '';
}

// Layout helpers — no-ops in SharedWorker (CSS/JS handled by Vite on main thread)
export function stylesheetLinkTag() { return ''; }
export function javascriptImportmapTags() { return ''; }
export function getAssetPath(name) { return `/assets/${name}`; }

// Application class for the SharedWorker
export class Application extends ApplicationServer {
  // Connected tab ports
  static ports = new Set();

  // Reference to the dedicated database Worker
  static dbWorker = null;

  // Start the SharedWorker application
  static async start() {
    // Spawn the dedicated database Worker
    this.dbWorker = new Worker(
      new URL('./db_worker.js', import.meta.url),
      { type: 'module' }
    );

    // Wire the dedicated Worker into the MessagePort adapter
    // so ActiveRecord queries flow through to the database
    setWorker(this.dbWorker);

    // Initialize database in the dedicated Worker
    await this.initDatabaseWorker();

    // Listen for tab connections
    self.onconnect = (event) => {
      const port = event.ports[0];
      this.ports.add(port);

      port.onmessage = async ({ data }) => {
        await this.handleMessage(port, data);
      };

      port.onmessageerror = () => {
        this.ports.delete(port);
      };

      port.start();
    };

    console.log('SharedWorker started');
  }

  // Initialize the database in the dedicated Worker
  static async initDatabaseWorker() {
    return new Promise((resolve, reject) => {
      const handler = ({ data }) => {
        if (data.type === 'ready') {
          this.dbWorker.removeEventListener('message', handler);
          console.log('Database Worker ready');
          resolve();
        } else if (data.type === 'error') {
          this.dbWorker.removeEventListener('message', handler);
          reject(new Error(data.error));
        }
      };

      this.dbWorker.addEventListener('message', handler);

      // DB_ADAPTER_PATH and DB_CONFIG are defined at build time by Vite
      this.dbWorker.postMessage({
        type: 'init',
        adapter: DB_ADAPTER_PATH,
        config: DB_CONFIG
      });
    });
  }

  // Handle incoming message from a tab
  static async handleMessage(port, message) {
    if (message.type !== 'fetch') return;

    const { id, method, url, headers, body } = message;

    try {
      // Build a Request-like object for Router.dispatch
      const req = {
        method: method || 'GET',
        url: url,
        headers: new Headers(headers || {}),
        _bodyText: body,
        _parsedBody: null,
        // Implement Fetch API body methods
        async text() { return this._bodyText || ''; },
        async json() { return JSON.parse(this._bodyText || '{}'); }
      };

      // Pre-parse body for form submissions
      if (body && (method === 'POST' || method === 'PATCH' || method === 'PUT' || method === 'DELETE')) {
        const contentType = headers?.['content-type'] || '';
        if (contentType.includes('application/json')) {
          try { req._parsedBody = JSON.parse(body); } catch {}
        } else {
          // URL-encoded form data
          const params = {};
          const pairs = body.split('&');
          for (const pair of pairs) {
            const [key, value] = pair.split('=');
            if (key) {
              const decodedKey = decodeURIComponent(key.replace(/\+/g, ' '));
              const decodedValue = decodeURIComponent((value || '').replace(/\+/g, ' '));
              const match = decodedKey.match(/^([^\[]+)\[([^\]]+)\]$/);
              if (match) {
                const [, model, field] = match;
                if (!params[model]) params[model] = {};
                params[model][field] = decodedValue;
              } else {
                params[decodedKey] = decodedValue;
              }
            }
          }
          req._parsedBody = params;
        }
      }

      // Dispatch through the server Router (returns a Fetch API Response)
      const response = await Router.dispatch(req);

      // Serialize the Response back to the tab
      const responseHeaders = {};
      response.headers.forEach((value, key) => {
        responseHeaders[key] = value;
      });

      port.postMessage({
        id,
        type: 'response',
        status: response.status,
        headers: responseHeaders,
        body: await response.text()
      });
    } catch (e) {
      console.error('SharedWorker dispatch error:', e);
      port.postMessage({
        id,
        type: 'response',
        status: 500,
        headers: { 'content-type': 'text/html' },
        body: `<h1>500 Internal Server Error</h1><pre>${e.stack}</pre>`
      });
    }
  }
}
