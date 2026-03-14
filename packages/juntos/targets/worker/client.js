// Ruby2JS-on-Rails Micro Framework - Worker Client Bridge (Main Thread)
// Presentation tier: intercepts Turbo navigation and form submissions,
// forwards them to the SharedWorker, and feeds synthetic Responses
// back to Turbo Drive.
//
// Falls back to the browser target if SharedWorker is unavailable.

import {
  RouterBase,
  ApplicationBase,
  createFlash,
  truncate,
  pluralize,
  dom_id,
  navigate,
  submitForm,
  formData,
  handleFormResult,
  setupFormHandlers
} from 'juntos/rails_base.js';

// Re-export base helpers
export { createFlash, truncate, pluralize, dom_id, navigate, submitForm, formData, handleFormResult, setupFormHandlers };

// Browser no-ops for layout helpers (CSS/JS handled by Vite)
export function stylesheetLinkTag() { return ''; }
export function javascriptImportmapTags() { return ''; }
export function getAssetPath(name) { return `/assets/${name}`; }

// Create a browser-side request context
export function createContext(params = {}) {
  const cookieHeader = document.cookie || '';
  const cookies = {};
  cookieHeader.split(';').forEach(c => {
    const eq = c.indexOf('=');
    if (eq > 0) {
      const key = c.substring(0, eq).trim();
      cookies[key] = decodeURIComponent(c.substring(eq + 1).trim());
    }
  });

  return {
    contentFor: {},
    flash: createFlash(cookieHeader),
    cookies: cookies,
    params: params,
    request: {
      path: location.pathname,
      method: 'GET',
      url: location.href,
      headers: null
    }
  };
}

// Worker bridge — sends fetch-like messages to SharedWorker
class WorkerBridge {
  constructor(worker) {
    this.port = worker.port;
    this.pending = new Map();
    this._readyResolve = null;
    this._readyReject = null;
    this._ready = new Promise((resolve, reject) => {
      this._readyResolve = resolve;
      this._readyReject = reject;
    });

    // Handle SharedWorker errors
    worker.onerror = (e) => {
      console.error('[juntos] SharedWorker error:', e);
      this._readyReject?.(new Error('SharedWorker failed to load'));
    };

    this.port.onmessage = ({ data }) => {
      if (data.type === 'ready') {
        this._readyResolve();
        return;
      }
      if (data.type === 'error') {
        console.error('[juntos] SharedWorker initialization error:', data.error);
        this._readyReject?.(new Error(data.error));
        return;
      }
      if (data.type === 'response' && data.id) {
        const resolver = this.pending.get(data.id);
        if (resolver) {
          this.pending.delete(data.id);
          resolver(data);
        }
      }
    };

    this.port.start();
  }

  // Wait for SharedWorker to finish initialization
  waitForReady() {
    return this._ready;
  }

  // Send a request to the SharedWorker and return a Promise for the response
  fetch(method, url, headers, body) {
    return new Promise((resolve) => {
      const id = crypto.randomUUID();
      this.pending.set(id, resolve);

      this.port.postMessage({
        id,
        type: 'fetch',
        method,
        url,
        headers,
        body
      });
    });
  }
}

// Turbo Streams via BroadcastChannel (same as browser target)
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
    if (html.startsWith('<turbo-stream') && typeof Turbo !== 'undefined' && Turbo.renderStreamMessage) {
      Turbo.renderStreamMessage(html);
    }
  }

  static subscribe(channelName, callback) {
    console.debug(`  [Subscribe] ${channelName}`);
    const channel = this.getChannel(channelName);
    channel.onmessage = (event) => {
      console.log(`  [Received] ${channelName}:`, event.data.substring(0, 100) + (event.data.length > 100 ? '...' : ''));
      if (event.data.startsWith('<turbo-stream') && typeof Turbo !== 'undefined' && Turbo.renderStreamMessage) {
        Turbo.renderStreamMessage(event.data);
      }
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

export { TurboBroadcast as BroadcastChannel };
globalThis.TurboBroadcast = TurboBroadcast;

export function turbo_stream_from(channelName) {
  TurboBroadcast.subscribe(channelName);
  return '';
}

// Stub Router for client — route matching happens in the SharedWorker
// We only need a minimal Router to satisfy imports; the real dispatch
// happens in the SharedWorker via WorkerBridge.
export class Router extends RouterBase {}

// Application class for the main thread (client bridge)
export class Application extends ApplicationBase {
  static bridge = null;

  static async start() {
    // Check for SharedWorker support
    if (typeof SharedWorker === 'undefined') {
      console.warn('[juntos] SharedWorker not available, falling back to browser target');
      // @vite-ignore: browser fallback is not bundled — it requires a different
      // database adapter (Dexie/IndexedDB) that may not be installed
      const browser = await import(/* @vite-ignore */ 'juntos/targets/browser/rails.js');
      return browser.Application.start();
    }

    try {
      // Create SharedWorker with Vite-fingerprinted URL
      const worker = new SharedWorker(
        new URL('./rails.js', import.meta.url),
        { type: 'module', name: 'juntos' }
      );

      this.bridge = new WorkerBridge(worker);

      // Wait for SharedWorker to finish initializing (database, migrations)
      await this.bridge.waitForReady();

      if (!this.layoutFn) {
        document.getElementById('loading').style.display = 'none';
        document.getElementById('app').style.display = 'block';
      }

      // Intercept Turbo fetch requests and forward to SharedWorker
      document.addEventListener('turbo:before-fetch-request', async (event) => {
        const fetchOptions = event.detail.fetchOptions;
        let method = fetchOptions.method?.toUpperCase() || 'GET';
        const url = new URL(event.detail.url);

        // Only intercept same-origin requests
        if (url.origin !== location.origin) return;

        event.preventDefault();

        // Extract body as string
        let bodyString = null;
        const body = fetchOptions.body;
        if (body instanceof FormData) {
          bodyString = new URLSearchParams(body).toString();
        } else if (body instanceof URLSearchParams) {
          bodyString = body.toString();
        } else if (typeof body === 'string') {
          bodyString = body;
        }

        // Build headers including cookies
        const headers = {
          cookie: document.cookie,
          accept: fetchOptions.headers?.Accept || fetchOptions.headers?.accept || 'text/html',
          'content-type': fetchOptions.headers?.['Content-Type']
            || fetchOptions.headers?.['content-type']
            || 'application/x-www-form-urlencoded'
        };

        // Send to SharedWorker
        const response = await this.bridge.fetch(method, url.href, headers, bodyString);

        // Apply Set-Cookie headers from response
        if (response.headers?.['set-cookie']) {
          document.cookie = response.headers['set-cookie'];
        }

        // Handle redirect responses
        if (response.status === 302 || response.status === 301) {
          const location = response.headers?.location || response.headers?.Location;
          if (location && typeof Turbo !== 'undefined') {
            Turbo.visit(location);
            return;
          }
        }

        // Create synthetic Response for Turbo
        event.detail.fetchRequest = {
          response: Promise.resolve(new Response(response.body, {
            status: response.status,
            headers: response.headers
          }))
        };
        event.detail.resume();
      });

      // Initial navigation
      let initialPath = location.pathname || '/';
      const redirectPath = sessionStorage.getItem('spa-redirect-path');
      if (redirectPath) {
        sessionStorage.removeItem('spa-redirect-path');
        initialPath = redirectPath;
        history.replaceState({}, '', initialPath);
      }

      if (this.layoutFn && typeof Turbo !== 'undefined') {
        Turbo.visit(initialPath, { action: 'replace' });
      }

      console.log('[juntos] Worker client bridge started');
    } catch (e) {
      const loadingEl = document.getElementById('loading');
      if (loadingEl) {
        loadingEl.innerHTML =
          `<p style="color: red;">Error: ${e.message}</p><pre>${e.stack}</pre>`;
      } else {
        document.body.innerHTML =
          `<p style="color: red;">Error: ${e.message}</p><pre>${e.stack}</pre>`;
      }
      console.error(e);
    }
  }
}
