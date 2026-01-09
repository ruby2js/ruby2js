// Ruby2JS-on-Rails Micro Framework - Capacitor Target
// Extends browser module with Capacitor plugin detection
// Runs in WebView with access to native device APIs

// Re-export everything from browser target
export * from '../browser/rails.js';

import { Application as BrowserApplication } from '../browser/rails.js';

// Capacitor-aware Application
export class Application extends BrowserApplication {
  // Check if running in Capacitor
  static get isCapacitor() {
    return typeof window !== 'undefined' &&
           typeof window.Capacitor !== 'undefined';
  }

  // Check if native platform (iOS/Android) vs web
  static get isNativePlatform() {
    return this.isCapacitor &&
           window.Capacitor.isNativePlatform();
  }

  // Get platform name: 'ios', 'android', or 'web'
  static get platform() {
    if (!this.isCapacitor) return 'web';
    return window.Capacitor.getPlatform();
  }

  // Override start to add Capacitor-specific initialization
  static async start() {
    if (this.isCapacitor) {
      console.log(`Running on Capacitor (${this.platform})`);

      // Wait for Capacitor to be ready on native platforms
      if (this.isNativePlatform) {
        await this.waitForCapacitor();
      }
    }

    // Call browser start
    return super.start();
  }

  // Wait for Capacitor plugins to be ready
  static async waitForCapacitor() {
    return new Promise((resolve) => {
      if (document.readyState === 'complete') {
        resolve();
      } else {
        document.addEventListener('deviceready', resolve, { once: true });
        // Fallback timeout in case deviceready doesn't fire
        setTimeout(resolve, 1000);
      }
    });
  }
}
