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
// Returns a custom element that the main thread picks up via connectedCallback
// (same pattern as turbo-cable-stream-source in @hotwired/turbo-rails)
export function turbo_stream_from(channelName) {
  return `<juntos-stream-source channel="${channelName}"></juntos-stream-source>`;
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

  // Reference to the dedicated database Worker (or MessagePort proxy)
  static dbWorker = null;

  // Fingerprinted DB Worker URL (received from main thread)
  static dbWorkerUrl = null;

  // The tab ID that hosts the dedicated Worker (null if Firefox direct mode)
  static dbWorkerHostId = null;

  // Whether we can create Workers directly (Firefox) or need tab delegation (Chrome)
  static canCreateWorker = null;

  // Map of tab ID → port
  static tabPorts = new Map();


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

      port.onmessage = async (event) => {
        const { data } = event;
        if (data.type === 'config') {
          if (data.dbWorkerUrl) this.dbWorkerUrl = data.dbWorkerUrl;
          if (data.tabId) this.tabPorts.set(data.tabId, port);
          configResolve();
          return;
        }
        if (data.type === 'create-db-worker') return; // handled by requestWorkerFromTab
        await this.handleMessage(port, data);
      };

      port.onmessageerror = () => {
        this.handleTabDisconnect(port);
      };

      port.start();

      // If already initialized, signal ready immediately
      if (this._ready) {
        port.postMessage({ type: 'ready' });
      }
    };

    // Listen for tab close announcements via BroadcastChannel
    const lifecycle = new globalThis.BroadcastChannel('juntos:lifecycle');
    lifecycle.onmessage = ({ data }) => {
      if (data.type === 'tab-closing' && data.tabId) {
        const port = this.tabPorts.get(data.tabId);
        if (port) {
          this.tabPorts.delete(data.tabId);
          this.ports.delete(port);
        }
        // If this tab was hosting the dedicated Worker, respawn
        if (data.tabId === this.dbWorkerHostId) {
          this.dbWorkerHostId = null;
          this.respawnDbWorker();
        }
      }
    };

    try {
      // Wait for config from the main thread (DB Worker URL)
      await configReady;

      // Spawn and initialize the dedicated database Worker
      await this.spawnDbWorker();

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

  // Create and initialize the dedicated database Worker
  static async spawnDbWorker(tabPort = null) {
    // Try directly first (works in Firefox); fall back to asking a
    // connected tab to create it (Chrome doesn't expose Worker in SharedWorker)
    if (this.canCreateWorker === null || this.canCreateWorker === true) {
      try {
        this.dbWorker = new Worker(this.dbWorkerUrl, { type: 'module' });
        this.canCreateWorker = true;
        this.dbWorkerHost = null;
      } catch {
        this.canCreateWorker = false;
      }
    }

    if (!this.canCreateWorker) {
      const hostTab = tabPort || this.ports.values().next().value;
      this.dbWorker = await this.requestWorkerFromTab(hostTab);
      // Find the tab ID for the host port
      for (const [id, port] of this.tabPorts) {
        if (port === hostTab) {
          this.dbWorkerHostId = id;
          break;
        }
      }
    }

    // Wire the dedicated Worker into the MessagePort adapter
    setWorker(this.dbWorker);

    // Wire for Active Storage file operations
    setStorageWorker(this.dbWorker);

    // Initialize database in the dedicated Worker
    await this.initDatabaseWorker();
  }

  // Respawn the dedicated Worker on another tab (when the host tab closes)
  static async respawnDbWorker() {
    if (this.ports.size === 0) {
      console.warn('No tabs available to respawn database Worker');
      return;
    }

    console.log('Database Worker host disconnected, respawning...');
    try {
      await this.spawnDbWorker();
      console.log('Database Worker respawned successfully');
    } catch (e) {
      console.error('Failed to respawn database Worker:', e);
    }
  }

  // Handle a tab disconnecting (via onmessageerror)
  static handleTabDisconnect(port) {
    this.ports.delete(port);
    // Find and remove tab ID
    for (const [id, p] of this.tabPorts) {
      if (p === port) {
        this.tabPorts.delete(id);
        if (id === this.dbWorkerHostId) {
          this.dbWorkerHostId = null;
          this.respawnDbWorker();
        }
        break;
      }
    }
  }

  // Ask a connected tab to create the dedicated Worker (Chrome fallback)
  // Returns a MessagePort that proxies to the Worker
  static requestWorkerFromTab(tab = null) {
    return new Promise((resolve, reject) => {
      tab = tab || this.ports.values().next().value;
      if (!tab) {
        reject(new Error('No connected tabs to create Worker'));
        return;
      }

      // Create a MessageChannel — one port for us, one for the Worker
      const channel = new MessageChannel();

      // Listen for the tab to confirm the Worker was created
      const handler = ({ data }) => {
        if (data.type === 'db-worker-created') {
          tab.removeEventListener?.('message', handler);
          // Use our end of the channel as the "worker" — it has the same
          // postMessage/addEventListener interface as a Worker
          channel.port1.start();
          resolve(channel.port1);
        } else if (data.type === 'db-worker-error') {
          tab.removeEventListener?.('message', handler);
          reject(new Error(data.error));
        }
      };
      tab.addEventListener('message', handler);

      // Ask the tab to create the Worker and wire it to port2
      tab.postMessage(
        { type: 'create-db-worker', url: this.dbWorkerUrl },
        [channel.port2]
      );
    });
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
              let decodedValue = decodeURIComponent((value || '').replace(/\+/g, ' '));

              // Reconstruct file uploads from data URIs
              // Format: datauri:<filename>:data:<mime>;base64,<data>
              if (typeof decodedValue === 'string' && decodedValue.startsWith('datauri:')) {
                const rest = decodedValue.slice(8); // after "datauri:"
                const colonIdx = rest.indexOf(':');
                const filename = rest.slice(0, colonIdx);
                const dataURI = rest.slice(colonIdx + 1);
                // Parse data URI: data:<mime>;base64,<data>
                const match2 = dataURI.match(/^data:([^;]+);base64,(.+)$/);
                if (match2) {
                  const binary = atob(match2[2]);
                  const bytes = new Uint8Array(binary.length);
                  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
                  decodedValue = new File([bytes], filename, { type: match2[1] });
                }
              }

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

      // Detect binary content types and base64-encode the body
      const contentType = responseHeaders['content-type'] || '';
      const isBinary = contentType.startsWith('image/') ||
        contentType.startsWith('audio/') ||
        contentType.startsWith('video/') ||
        contentType === 'application/octet-stream' ||
        contentType === 'application/pdf';

      let body;
      if (isBinary) {
        const buffer = await response.arrayBuffer();
        const bytes = new Uint8Array(buffer);
        let binary = '';
        for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
        body = btoa(binary);
      } else {
        body = await response.text();
      }

      port.postMessage({
        id,
        type: 'response',
        status: response.status,
        headers: responseHeaders,
        body,
        binary: isBinary
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
