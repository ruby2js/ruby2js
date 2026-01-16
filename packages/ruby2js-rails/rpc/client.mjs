/**
 * RPC Client for Ruby2JS-Rails
 *
 * Provides a transport layer for making RPC calls from browser to server.
 * Used by the ActiveRecord RPC adapter to proxy model operations.
 *
 * Features:
 * - Single endpoint (/__rpc) with header-based action routing
 * - CSRF token protection (Rails-style authenticity tokens)
 * - JSON serialization
 */

/**
 * Error class for RPC failures
 */
export class RPCError extends Error {
  constructor(responseOrMessage, status = null) {
    if (typeof responseOrMessage === 'string') {
      super(responseOrMessage);
      this.status = status;
    } else if (responseOrMessage instanceof Response) {
      super(`RPC failed: ${responseOrMessage.status} ${responseOrMessage.statusText}`);
      this.status = responseOrMessage.status;
      this.response = responseOrMessage;
    } else if (responseOrMessage && typeof responseOrMessage === 'object') {
      super(responseOrMessage.message || 'RPC error');
      this.code = responseOrMessage.code;
      this.details = responseOrMessage.details;
    } else {
      super('Unknown RPC error');
    }
    this.name = 'RPCError';
  }
}

/**
 * Create an RPC client configured for the application
 *
 * @param {Object} options - Configuration options
 * @param {string} options.endpoint - RPC endpoint URL (default: '/__rpc')
 * @param {Function} options.getToken - Function to retrieve CSRF token
 * @returns {Function} RPC function: (action, args) => Promise<result>
 *
 * @example
 * const rpc = createRPCClient();
 * const user = await rpc('User.find', [1]);
 * const users = await rpc('User.where', [{ active: true }]);
 */
export function createRPCClient(options = {}) {
  const endpoint = options.endpoint || '/__rpc';
  const getToken = options.getToken ||
    (() => document.querySelector('meta[name="csrf-token"]')?.content);

  return async function rpc(action, args = []) {
    const token = getToken();

    const headers = {
      'Content-Type': 'application/json',
      'X-RPC-Action': action
    };

    // Only include token if available (might be null in some contexts)
    if (token) {
      headers['X-Authenticity-Token'] = token;
    }

    const response = await fetch(endpoint, {
      method: 'POST',
      headers,
      body: JSON.stringify({ args }),
      credentials: 'same-origin' // Include cookies for session
    });

    if (!response.ok) {
      throw new RPCError(response);
    }

    const data = await response.json();

    if (data.error) {
      throw new RPCError(data.error);
    }

    return data.result;
  };
}

// Default singleton client instance
let defaultClient = null;

/**
 * Get or create the default RPC client
 *
 * @param {Object} options - Options passed to createRPCClient if creating new instance
 * @returns {Function} RPC function
 */
export function getClient(options = {}) {
  if (!defaultClient) {
    defaultClient = createRPCClient(options);
  }
  return defaultClient;
}

/**
 * Make an RPC call using the default client
 *
 * @param {string} action - Action name (e.g., 'User.find', 'Post.create')
 * @param {Array} args - Arguments to pass to the action
 * @returns {Promise<any>} Result from the server
 *
 * @example
 * // In your module:
 * // import { rpc } from 'ruby2js-rails/rpc/client.mjs';
 * const user = await rpc('User.find', [1]);
 */
export async function rpc(action, args = []) {
  return getClient()(action, args);
}
