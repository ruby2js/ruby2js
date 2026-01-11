// Ruby2JS-on-Rails Micro Framework - Tauri Target
// Extends browser module with Tauri API integration
// Runs in Tauri's WebView with access to Rust backend via IPC

// Re-export everything from browser target
export * from '../browser/rails.js';

import { Application as BrowserApplication } from '../browser/rails.js';

// Tauri-aware Application
export class Application extends BrowserApplication {
  // Check if running in Tauri
  static get isTauri() {
    return typeof window !== 'undefined' &&
           typeof window.__TAURI__ !== 'undefined';
  }

  // Access to Tauri's internal APIs (if available)
  static get tauriInternals() {
    return window.__TAURI_INTERNALS__;
  }

  // Override start to add Tauri-specific initialization
  static async start() {
    if (this.isTauri) {
      console.log('Running in Tauri WebView');
      this.setupTauriListeners();
    }

    // Call browser start
    return super.start();
  }

  // Set up event listeners from Tauri backend
  static setupTauriListeners() {
    // Listen for events from Rust backend using Tauri's event system
    if (window.__TAURI__?.event?.listen) {
      // Example: listen for quick-capture event
      window.__TAURI__.event.listen('quick-capture', () => {
        document.dispatchEvent(new CustomEvent('tauri:quick-capture'));
      });

      // Example: listen for window focus/blur
      window.__TAURI__.event.listen('tauri://focus', () => {
        document.dispatchEvent(new CustomEvent('tauri:window-focus'));
      });

      window.__TAURI__.event.listen('tauri://blur', () => {
        document.dispatchEvent(new CustomEvent('tauri:window-blur'));
      });
    }
  }

  // Invoke a Tauri command (calls Rust backend)
  static async invoke(cmd, args = {}) {
    if (window.__TAURI__?.core?.invoke) {
      return window.__TAURI__.core.invoke(cmd, args);
    }
    throw new Error('Tauri invoke API not available');
  }

  // Emit an event to the Tauri backend
  static async emit(event, payload) {
    if (window.__TAURI__?.event?.emit) {
      return window.__TAURI__.event.emit(event, payload);
    }
    throw new Error('Tauri event API not available');
  }

  // Listen for an event from the Tauri backend
  static async listen(event, callback) {
    if (window.__TAURI__?.event?.listen) {
      return window.__TAURI__.event.listen(event, callback);
    }
    throw new Error('Tauri event API not available');
  }

  // Open a URL in the default browser
  static async openUrl(url) {
    if (window.__TAURI__?.shell?.open) {
      return window.__TAURI__.shell.open(url);
    }
    // Fallback for non-Tauri environments
    window.open(url, '_blank');
  }
}
