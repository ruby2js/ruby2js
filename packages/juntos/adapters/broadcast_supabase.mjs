// Supabase Realtime Broadcast Adapter for Turbo Streams
// Uses Supabase Realtime for WebSocket-based pub/sub
// Works with Vercel, Cloudflare, and other serverless platforms

import { createClient } from '@supabase/supabase-js';

let supabase = null;
let realtimeChannel = null;

// Configuration - set via initBroadcast() or environment variables
const config = {
  url: null,
  key: null
};

// Initialize the Supabase client for broadcasting
export function initBroadcast(options = {}) {
  config.url = options.url || process.env.SUPABASE_URL;
  config.key = options.key || process.env.SUPABASE_ANON_KEY;

  if (!config.url || !config.key) {
    console.warn('Supabase broadcast: SUPABASE_URL and SUPABASE_ANON_KEY required');
    return null;
  }

  supabase = createClient(config.url, config.key, {
    auth: {
      autoRefreshToken: false,
      persistSession: false
    }
  });

  console.log('Supabase Realtime broadcast initialized');
  return supabase;
}

// Server-side: Broadcast a turbo-stream message to all subscribers
// Called by model broadcast_*_to methods
export function broadcast(channelName, html) {
  if (!supabase) {
    initBroadcast();
  }

  if (!supabase) {
    console.warn(`Supabase broadcast: not initialized, skipping broadcast to ${channelName}`);
    return;
  }

  // Use Supabase Realtime Broadcast feature
  // This sends a message to all clients subscribed to the channel
  const channel = supabase.channel(channelName);

  channel.send({
    type: 'broadcast',
    event: 'turbo-stream',
    payload: { html }
  }).then(() => {
    console.log(`  Broadcast to ${channelName}`);
  }).catch((err) => {
    console.error(`  Broadcast error: ${err.message}`);
  });
}

// Client-side: Subscribe to turbo-stream messages on a channel
// Used by turbo_stream_from helper in views
// Returns empty string for ERB interpolation compatibility
export function subscribe(channelName, callback) {
  if (!supabase) {
    initBroadcast();
  }

  if (!supabase) {
    console.warn(`Supabase broadcast: not initialized, cannot subscribe to ${channelName}`);
    return '';
  }

  const channel = supabase.channel(channelName);

  channel
    .on('broadcast', { event: 'turbo-stream' }, (payload) => {
      const html = payload.payload?.html;
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
    })
    .subscribe((status) => {
      if (status === 'SUBSCRIBED') {
        console.log(`  Subscribed to ${channelName}`);
      }
    });

  // Track the channel for cleanup
  realtimeChannel = channel;

  return '';
}

// Unsubscribe from a channel
export function unsubscribe(channelName) {
  if (realtimeChannel) {
    supabase.removeChannel(realtimeChannel);
    realtimeChannel = null;
    console.log(`  Unsubscribed from ${channelName}`);
  }
}

// TurboBroadcast class for compatibility with existing rails.js exports
export class TurboBroadcast {
  static broadcast(channelName, html) {
    return broadcast(channelName, html);
  }

  static subscribe(channelName, callback) {
    return subscribe(channelName, callback);
  }

  static unsubscribe(channelName) {
    return unsubscribe(channelName);
  }

  // Server-side message handling (no-op for Supabase - uses Realtime)
  static handleMessage(ws, data) {
    // Not used - Supabase Realtime handles this
  }

  static cleanup(ws) {
    // Not used - Supabase Realtime handles this
  }
}

// Export as BroadcastChannel for model compatibility
export { TurboBroadcast as BroadcastChannel };

// Helper function for views to subscribe to turbo streams
// Usage in ERB: <%= turbo_stream_from "chat_room" %>
export function turbo_stream_from(channelName) {
  subscribe(channelName);
  return '';
}
