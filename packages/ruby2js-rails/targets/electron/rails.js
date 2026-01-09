// Ruby2JS-on-Rails Micro Framework - Electron Target (Renderer Process)
// Extends browser module with Electron IPC integration
// Runs in Electron's renderer with access to preload APIs

// Re-export everything from browser target
export * from '../browser/rails.js';

import { Application as BrowserApplication } from '../browser/rails.js';

// Electron-aware Application (Renderer Process)
export class Application extends BrowserApplication {
  // Check if running in Electron
  static get isElectron() {
    return typeof window !== 'undefined' &&
           typeof window.electronAPI !== 'undefined';
  }

  // Access to preload-exposed APIs (safe IPC)
  static get electronAPI() {
    return window.electronAPI;
  }

  // Override start to add Electron-specific initialization
  static async start() {
    if (this.isElectron) {
      console.log('Running in Electron renderer');
      this.setupElectronListeners();
    }

    // Call browser start
    return super.start();
  }

  // Set up IPC event listeners from main process
  static setupElectronListeners() {
    const api = this.electronAPI;
    if (!api) return;

    // Listen for quick-capture event from main process (tray/shortcut)
    if (api.onQuickCapture) {
      api.onQuickCapture(() => {
        console.log('Quick capture triggered from main process');
        // Dispatch custom event for Stimulus controllers to handle
        document.dispatchEvent(new CustomEvent('electron:quick-capture'));
      });
    }

    // Listen for window show/hide events
    if (api.onWindowShow) {
      api.onWindowShow(() => {
        document.dispatchEvent(new CustomEvent('electron:window-show'));
      });
    }

    if (api.onWindowHide) {
      api.onWindowHide(() => {
        document.dispatchEvent(new CustomEvent('electron:window-hide'));
      });
    }
  }

  // Send message to main process
  static sendToMain(channel, ...args) {
    if (this.electronAPI?.send) {
      this.electronAPI.send(channel, ...args);
    }
  }

  // Invoke main process and get response
  static async invokeMain(channel, ...args) {
    if (this.electronAPI?.invoke) {
      return this.electronAPI.invoke(channel, ...args);
    }
    throw new Error('electronAPI.invoke not available');
  }
}
