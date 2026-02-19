// Pusher Broadcast Adapter for Turbo Streams
// Uses Pusher for WebSocket-based pub/sub
// Works with Vercel, Cloudflare, and other serverless platforms
// Recommended by Vercel for real-time features

// Server-side: pusher (Node.js)
// Client-side: pusher-js (browser)

let pusherServer = null;
let pusherClient = null;
let subscribedChannels = new Map();

// Configuration - set via initBroadcast() or environment variables
const config = {
  appId: null,
  key: null,
  secret: null,
  cluster: null
};

// Initialize Pusher for server-side broadcasting
export async function initBroadcast(options = {}) {
  config.appId = options.appId || process.env.PUSHER_APP_ID;
  config.key = options.key || process.env.PUSHER_KEY || process.env.NEXT_PUBLIC_PUSHER_KEY;
  config.secret = options.secret || process.env.PUSHER_SECRET;
  config.cluster = options.cluster || process.env.PUSHER_CLUSTER || process.env.NEXT_PUBLIC_PUSHER_CLUSTER || 'us2';

  // Server-side initialization (Node.js)
  if (config.appId && config.secret) {
    try {
      const Pusher = (await import('pusher')).default;
      pusherServer = new Pusher({
        appId: config.appId,
        key: config.key,
        secret: config.secret,
        cluster: config.cluster,
        useTLS: true
      });
      console.log('Pusher server initialized');
    } catch (e) {
      console.warn('Pusher server package not available:', e.message);
    }
  }

  // Client-side initialization (browser)
  if (typeof window !== 'undefined' && config.key) {
    try {
      const PusherClient = (await import('pusher-js')).default;
      pusherClient = new PusherClient(config.key, {
        cluster: config.cluster
      });
      console.log('Pusher client initialized');
    } catch (e) {
      console.warn('Pusher client package not available:', e.message);
    }
  }

  return { server: pusherServer, client: pusherClient };
}

// Server-side: Broadcast a turbo-stream message to all subscribers
// Called by model broadcast_*_to methods
export async function broadcast(channelName, html) {
  if (!pusherServer) {
    await initBroadcast();
  }

  if (!pusherServer) {
    console.warn(`Pusher broadcast: server not initialized, skipping broadcast to ${channelName}`);
    return;
  }

  try {
    await pusherServer.trigger(channelName, 'turbo-stream', { html });
    console.log(`  Broadcast to ${channelName}`);
  } catch (err) {
    console.error(`  Broadcast error: ${err.message}`);
  }
}

// Client-side: Subscribe to turbo-stream messages on a channel
// Used by turbo_stream_from helper in views
// Returns empty string for ERB interpolation compatibility
export async function subscribe(channelName, callback) {
  if (!pusherClient) {
    await initBroadcast();
  }

  if (!pusherClient) {
    console.warn(`Pusher broadcast: client not initialized, cannot subscribe to ${channelName}`);
    return '';
  }

  const channel = pusherClient.subscribe(channelName);

  channel.bind('turbo-stream', (data) => {
    const html = data?.html;
    if (html) {
      // Render the turbo-stream via Turbo
      if (typeof Turbo !== 'undefined' && Turbo.renderStreamMessage) {
        Turbo.renderStreamMessage(html);
      }
      // Also call custom callback if provided
      if (callback) {
        callback(html);
      }
    }
  });

  subscribedChannels.set(channelName, channel);
  console.log(`  Subscribed to ${channelName}`);

  return '';
}

// Unsubscribe from a channel
export function unsubscribe(channelName) {
  if (pusherClient && subscribedChannels.has(channelName)) {
    pusherClient.unsubscribe(channelName);
    subscribedChannels.delete(channelName);
    console.log(`  Unsubscribed from ${channelName}`);
  }
}

// TurboBroadcast class for compatibility with existing rails.js exports
export class TurboBroadcast {
  static async broadcast(channelName, html) {
    return broadcast(channelName, html);
  }

  static async subscribe(channelName, callback) {
    return subscribe(channelName, callback);
  }

  static unsubscribe(channelName) {
    return unsubscribe(channelName);
  }

  // Server-side message handling (no-op for Pusher - uses HTTP trigger)
  static handleMessage(ws, data) {
    // Not used - Pusher handles this via HTTP API
  }

  static cleanup(ws) {
    // Not used - Pusher handles this
  }
}

// Export as BroadcastChannel for model compatibility
export { TurboBroadcast as BroadcastChannel };

// Helper function for views to subscribe to turbo streams
// Usage in ERB: <%= turbo_stream_from "chat_room" %>
export async function turbo_stream_from(channelName) {
  await subscribe(channelName);
  return '';
}
