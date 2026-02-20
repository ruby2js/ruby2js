// Ruby2JS-on-Rails Micro Framework - Electrobun Target (Renderer Process)
// Extends browser module with Electrobun typed RPC integration
// Runs in Electrobun's system WebView with access to Bun backend via RPC

// Re-export everything from browser target
export * from '../browser/rails.js';

import { Application as BrowserApplication } from '../browser/rails.js';

// Electrobun-aware Application (WebView Process)
export class Application extends BrowserApplication {
  static #electrobun = null;

  // Check if running in Electrobun
  // Electrobun injects __electrobunWindowId into every webview automatically
  static get isElectrobun() {
    return typeof window !== 'undefined' &&
           typeof window.__electrobunWindowId !== 'undefined';
  }

  // Access to Electroview instance
  static get electrobun() {
    return this.#electrobun;
  }

  // Override start to add Electrobun-specific initialization
  static async start() {
    if (this.isElectrobun) {
      console.log('Running in Electrobun WebView');
      await this.initElectrobun();
    }

    // Call browser start
    return super.start();
  }

  // Initialize Electroview with RPC handlers
  static async initElectrobun() {
    try {
      const { Electroview } = await import('electrobun/view');
      const rpc = this.defineRPC(Electroview);
      this.#electrobun = new Electroview({ rpc });
      this.setupElectrobunListeners();
    } catch (e) {
      console.warn('Failed to initialize Electrobun:', e.message);
    }
  }

  // Default RPC definition — apps override this for custom commands
  // The RPC schema defines what the webview can receive from the Bun process
  static defineRPC(Electroview) {
    return Electroview.defineRPC({
      handlers: {
        requests: {},
        messages: {
          quickCapture: () => {
            document.dispatchEvent(new CustomEvent('electrobun:quick-capture'));
          },
          navigate: ({path}) => {
            document.dispatchEvent(new CustomEvent('electrobun:navigate', { detail: { path } }));
          }
        }
      }
    });
  }

  // Set up event listeners bridged from Bun process
  static setupElectrobunListeners() {
    // Listen for navigate messages and handle them
    document.addEventListener('electrobun:navigate', (event) => {
      const path = event.detail?.path;
      if (path) {
        history.pushState({}, '', path);
        // Use dynamic import to avoid circular dependency
        import('../browser/rails.js').then(({ Router }) => {
          Router.dispatch(path);
        });
      }
    });
  }

  // Send a request to the Bun main process (async, returns response)
  static async invoke(method, args) {
    if (!this.#electrobun?.rpc?.request?.[method]) {
      throw new Error(`Electrobun RPC request '${method}' not available`);
    }
    return this.#electrobun.rpc.request[method](args);
  }

  // Send a fire-and-forget message to the Bun main process
  static send(method, args) {
    if (this.#electrobun?.rpc?.send?.[method]) {
      this.#electrobun.rpc.send[method](args);
    }
  }
}
