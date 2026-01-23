// Simple Turbo Streams WebSocket client for edge platforms
// Uses base @hotwired/turbo's connectStreamSource API
// No Action Cable protocol, no pings required - ideal for Durable Objects hibernation

import { connectStreamSource, disconnectStreamSource } from '@hotwired/turbo';

// Simple WebSocket connection manager
class TurboStreamSocket {
  constructor() {
    this.socket = null;
    this.subscriptions = new Map(); // stream name -> callback
    this.reconnectAttempts = 0;
    this.maxReconnectAttempts = 5;
    this.reconnectDelay = 1000;
  }

  connect() {
    if (this.socket?.readyState === WebSocket.OPEN) return;

    const protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
    const url = `${protocol}//${location.host}/cable`;

    this.socket = new WebSocket(url);

    this.socket.onopen = () => {
      console.log('[TurboStreamSocket] Connected');
      this.reconnectAttempts = 0;
      // Resubscribe to all channels after reconnect
      for (const stream of this.subscriptions.keys()) {
        this.sendSubscribe(stream);
      }
    };

    this.socket.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);

        // Simple protocol: { stream: "name", html: "<turbo-stream>..." }
        if (data.stream && data.html) {
          const callback = this.subscriptions.get(data.stream);
          if (callback) {
            callback(data.html);
          }
        }
      } catch (e) {
        // Not JSON - might be raw HTML for broadcast
        console.warn('[TurboStreamSocket] Unexpected message format:', e);
      }
    };

    this.socket.onclose = (event) => {
      console.log('[TurboStreamSocket] Disconnected', event.code);
      this.attemptReconnect();
    };

    this.socket.onerror = (error) => {
      console.error('[TurboStreamSocket] Error:', error);
    };
  }

  attemptReconnect() {
    if (this.reconnectAttempts >= this.maxReconnectAttempts) {
      console.error('[TurboStreamSocket] Max reconnect attempts reached');
      return;
    }

    this.reconnectAttempts++;
    const delay = this.reconnectDelay * Math.pow(2, this.reconnectAttempts - 1);
    console.log(`[TurboStreamSocket] Reconnecting in ${delay}ms...`);

    setTimeout(() => this.connect(), delay);
  }

  sendSubscribe(stream) {
    if (this.socket?.readyState === WebSocket.OPEN) {
      this.socket.send(JSON.stringify({ type: 'subscribe', stream }));
    }
  }

  subscribe(stream, callback) {
    this.subscriptions.set(stream, callback);
    this.connect(); // Ensure connected
    this.sendSubscribe(stream);
  }

  unsubscribe(stream) {
    this.subscriptions.delete(stream);
    if (this.socket?.readyState === WebSocket.OPEN) {
      this.socket.send(JSON.stringify({ type: 'unsubscribe', stream }));
    }
    // Close socket if no more subscriptions
    if (this.subscriptions.size === 0 && this.socket) {
      this.socket.close();
      this.socket = null;
    }
  }
}

// Singleton socket instance
const socket = new TurboStreamSocket();

// Custom element that integrates with Turbo's stream source API
// Usage: <turbo-stream-source stream="articles"></turbo-stream-source>
class TurboStreamSourceElement extends HTMLElement {
  connectedCallback() {
    const stream = this.getAttribute('stream');
    if (!stream) return;

    // Create a stream source that dispatches MessageEvents
    this.streamSource = {
      addEventListener: (type, listener) => {
        if (type === 'message') {
          this._messageListener = listener;
        }
      },
      removeEventListener: (type, listener) => {
        if (type === 'message' && this._messageListener === listener) {
          this._messageListener = null;
        }
      }
    };

    // Subscribe to the stream
    socket.subscribe(stream, (html) => {
      if (this._messageListener) {
        // Dispatch as MessageEvent - Turbo processes the data
        const event = new MessageEvent('message', { data: html });
        this._messageListener(event);
      }
    });

    // Connect to Turbo's stream processing
    connectStreamSource(this.streamSource);
    console.log(`[TurboStreamSource] Subscribed to: ${stream}`);
  }

  disconnectedCallback() {
    const stream = this.getAttribute('stream');
    if (stream) {
      socket.unsubscribe(stream);
      console.log(`[TurboStreamSource] Unsubscribed from: ${stream}`);
    }
    if (this.streamSource) {
      disconnectStreamSource(this.streamSource);
    }
  }
}

// Register the custom element
if (!customElements.get('turbo-stream-source')) {
  customElements.define('turbo-stream-source', TurboStreamSourceElement);
}

// Export for programmatic use
export { socket as TurboStreamSocket, TurboStreamSourceElement };
