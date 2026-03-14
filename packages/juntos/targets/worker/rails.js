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
  getCSRF,
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

// Disable CSRF validation — the worker target has no network boundary
// to protect against (all requests come from the same origin via MessagePort)
getCSRF().validateToken = async () => true;

import * as adapter from 'juntos/adapters/active_record_worker.mjs';
import { setWorker } from 'juntos/adapters/active_record_worker.mjs';
import { setStorageWorker, initActiveStorage } from 'juntos/adapters/active_storage_worker.mjs';

// Re-export base helpers
export { createContext, createFlash, truncate, pluralize, dom_id, navigate, submitForm, formData, handleFormResult, setupFormHandlers };

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
  // Propagate configuration to the parent class (ApplicationServer)
  // so Router.htmlResponse() can access the layout via Application.wrapInLayout()
  static configure(options) {
    super.configure(options);
    ApplicationServer.configure(options);
  }

  // Connected tab ports
  static ports = new Set();

  // Reference to the dedicated database Worker
  static dbWorker = null;

  // Fingerprinted DB Worker URL (received from main thread)
  static dbWorkerUrl = null;


  // Start the SharedWorker application
  static async start() {
    this._ready = false;
    let configResolve;
    const configReady = new Promise(resolve => { configResolve = resolve; });

    // Listen for tab connections immediately (before async init)
    // so we don't miss the first tab's connect event
    self.onconnect = (event) => {
      const port = event.ports[0];
      this.ports.add(port);

      port.onmessage = async ({ data }) => {
        if (data.type === 'config') {
          if (data.dbWorkerUrl) this.dbWorkerUrl = data.dbWorkerUrl;
          configResolve();
          return;
        }
        await this.handleMessage(port, data);
      };

      port.onmessageerror = () => {
        this.ports.delete(port);
      };

      port.start();

      // If already initialized, signal ready immediately
      if (this._ready) {
        port.postMessage({ type: 'ready' });
      }
    };

    try {
      // Wait for config from the main thread (DB Worker URL)
      await configReady;

      // Spawn the dedicated database Worker using the fingerprinted URL
      this.dbWorker = new Worker(this.dbWorkerUrl, { type: 'module' });

      // Wire the dedicated Worker into the MessagePort adapter
      // so ActiveRecord queries flow through to the database
      setWorker(this.dbWorker);

      // Wire the dedicated Worker for Active Storage file operations
      setStorageWorker(this.dbWorker);

      // Initialize database in the dedicated Worker
      await this.initDatabaseWorker();

      // Wire the adapter for model registry
      this.activeRecordModule = adapter;
      if (adapter.modelRegistry && this.models) {
        Object.assign(adapter.modelRegistry, this.models);
      }

      // Initialize Active Storage
      try {
        await initActiveStorage();
      } catch (e) {
        // Active Storage not available - no-op
      }

      // Run migrations and seeds
      const { wasFresh } = await this.runMigrations(adapter);
      if (this.seeds && wasFresh) {
        await this.seeds.run();
      }

      // Mark as ready and notify all connected tabs
      this._ready = true;
      for (const port of this.ports) {
        port.postMessage({ type: 'ready' });
      }

      console.log('SharedWorker started');
    } catch (e) {
      console.error('SharedWorker initialization failed:', e);
      // Notify all connected tabs of the error
      for (const port of this.ports) {
        port.postMessage({ type: 'error', error: e.message });
      }
    }
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

      // DB_CONFIG is defined at build time by Vite
      this.dbWorker.postMessage({
        type: 'init',
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
