/**
 * RPC Server for Ruby2JS-Rails
 *
 * Handles RPC requests from the client, dispatching to registered handlers.
 * Designed to work with Node.js http, Cloudflare Workers, Vercel Edge, etc.
 *
 * Features:
 * - Single endpoint (/__rpc) with header-based action routing
 * - CSRF token validation
 * - Model operation auto-registration
 * - Extensible handler registry
 */

import { randomBytes, createHmac } from 'node:crypto';

/**
 * Registry for RPC handlers
 * Maps action names (e.g., 'User.find') to handler functions
 */
export class RPCRegistry {
  constructor() {
    this.handlers = new Map();
  }

  /**
   * Register a handler for an action
   * @param {string} action - Action name (e.g., 'User.find')
   * @param {Function} handler - Async function to handle the action
   */
  register(action, handler) {
    this.handlers.set(action, handler);
  }

  /**
   * Get a handler for an action
   * @param {string} action - Action name
   * @returns {Function|undefined} Handler function
   */
  get(action) {
    return this.handlers.get(action);
  }

  /**
   * Check if a handler exists
   * @param {string} action - Action name
   * @returns {boolean}
   */
  has(action) {
    return this.handlers.has(action);
  }

  /**
   * Register all CRUD operations for a model
   * @param {string} name - Model name (e.g., 'User')
   * @param {Object} Model - Model class with static methods
   */
  registerModel(name, Model) {
    // Static methods
    this.register(`${name}.find`, (id) => Model.find(id));
    this.register(`${name}.all`, () => Model.all());
    this.register(`${name}.where`, (conditions) => Model.where(conditions));
    this.register(`${name}.create`, (attrs) => Model.create(attrs));
    this.register(`${name}.findBy`, (conditions) => Model.findBy(conditions));

    // Instance methods (need id + data)
    this.register(`${name}.update`, async (id, attrs) => {
      const record = await Model.find(id);
      if (!record) throw new Error(`${name} not found: ${id}`);
      await record.update(attrs);
      return record.attributes;
    });

    this.register(`${name}.destroy`, async (id) => {
      const record = await Model.find(id);
      if (!record) throw new Error(`${name} not found: ${id}`);
      await record.destroy();
      return { success: true };
    });

    this.register(`${name}.save`, async (id, attrs) => {
      const record = await Model.find(id);
      if (!record) throw new Error(`${name} not found: ${id}`);
      Object.assign(record.attributes, attrs);
      await record.save();
      return record.attributes;
    });
  }
}

/**
 * CSRF Token Manager
 * Generates and validates tokens for request authenticity
 */
export class CSRFProtection {
  constructor(secret = null) {
    // Use provided secret or generate one (should be consistent across restarts in production)
    this.secret = secret || process.env.CSRF_SECRET || randomBytes(32).toString('hex');
  }

  /**
   * Generate a CSRF token for a session
   * @param {string} sessionId - Session identifier
   * @returns {string} Token
   */
  generateToken(sessionId = '') {
    const timestamp = Date.now().toString(36);
    const random = randomBytes(16).toString('hex');
    const data = `${timestamp}:${random}:${sessionId}`;
    const signature = this.sign(data);
    return Buffer.from(`${data}:${signature}`).toString('base64');
  }

  /**
   * Validate a CSRF token
   * @param {string} token - Token from request header
   * @param {string} sessionId - Session identifier (optional)
   * @returns {boolean} Whether token is valid
   */
  validateToken(token, sessionId = '') {
    if (!token) return false;

    try {
      const decoded = Buffer.from(token, 'base64').toString();
      const parts = decoded.split(':');
      if (parts.length !== 4) return false;

      const [timestamp, random, tokenSessionId, signature] = parts;
      const data = `${timestamp}:${random}:${tokenSessionId}`;

      // Verify signature
      if (signature !== this.sign(data)) return false;

      // Optionally verify session ID matches
      if (sessionId && tokenSessionId !== sessionId) return false;

      // Check token age (valid for 24 hours)
      const tokenTime = parseInt(timestamp, 36);
      const maxAge = 24 * 60 * 60 * 1000; // 24 hours
      if (Date.now() - tokenTime > maxAge) return false;

      return true;
    } catch {
      return false;
    }
  }

  /**
   * Sign data with HMAC
   * @private
   */
  sign(data) {
    return createHmac('sha256', this.secret).update(data).digest('hex').slice(0, 16);
  }
}

// Default instances
let defaultRegistry = null;
let defaultCSRF = null;

/**
 * Get or create the default RPC registry
 * @returns {RPCRegistry}
 */
export function getRegistry() {
  if (!defaultRegistry) {
    defaultRegistry = new RPCRegistry();
  }
  return defaultRegistry;
}

/**
 * Get or create the default CSRF protection
 * @returns {CSRFProtection}
 */
export function getCSRF() {
  if (!defaultCSRF) {
    defaultCSRF = new CSRFProtection();
  }
  return defaultCSRF;
}

/**
 * Create an RPC request handler
 *
 * @param {Object} options - Configuration options
 * @param {RPCRegistry} options.registry - Handler registry (default: global)
 * @param {CSRFProtection} options.csrf - CSRF protection (default: global)
 * @param {boolean} options.requireCSRF - Whether to require CSRF tokens (default: true)
 * @returns {Function} Handler function
 */
export function createRPCHandler(options = {}) {
  const registry = options.registry || getRegistry();
  const csrf = options.csrf || getCSRF();
  const requireCSRF = options.requireCSRF !== false;

  /**
   * Handle an RPC request (Node.js style)
   *
   * @param {http.IncomingMessage} req - Node.js request
   * @param {http.ServerResponse} res - Node.js response
   * @returns {Promise<boolean>} Whether the request was handled
   */
  return async function handleRPC(req, res) {
    // Check if this is an RPC request
    const action = req.headers['x-rpc-action'];
    if (!action) {
      return false; // Not an RPC request, let normal routing handle it
    }

    // Validate CSRF token
    if (requireCSRF) {
      const token = req.headers['x-csrf-token'];
      if (!csrf.validateToken(token)) {
        res.writeHead(422, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: { message: 'Invalid authenticity token', code: 'CSRF_INVALID' } }));
        return true;
      }
    }

    // Find handler
    const handler = registry.get(action);
    if (!handler) {
      res.writeHead(404, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: { message: `Unknown action: ${action}`, code: 'NOT_FOUND' } }));
      return true;
    }

    // Parse request body
    let args = [];
    try {
      const body = await parseBody(req);
      args = body.args || [];
    } catch (e) {
      res.writeHead(400, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: { message: 'Invalid request body', code: 'PARSE_ERROR' } }));
      return true;
    }

    // Execute handler
    try {
      console.log(`RPC: ${action}(${args.map(a => JSON.stringify(a)).join(', ')})`);
      const result = await handler(...args);

      // Serialize result (handle model instances)
      const serialized = serializeResult(result);

      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ result: serialized }));
    } catch (e) {
      console.error(`RPC Error [${action}]:`, e.message);
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: { message: e.message, code: 'HANDLER_ERROR' } }));
    }

    return true;
  };
}

/**
 * Parse request body as JSON
 * @private
 */
function parseBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      try {
        resolve(body ? JSON.parse(body) : {});
      } catch (e) {
        reject(e);
      }
    });
    req.on('error', reject);
  });
}

/**
 * Serialize a result for JSON response
 * Handles model instances with .attributes property
 * @private
 */
function serializeResult(result) {
  if (result === null || result === undefined) {
    return result;
  }

  // Handle model instances
  if (result.attributes && typeof result.attributes === 'object') {
    return { ...result.attributes, id: result.id };
  }

  // Handle arrays of models
  if (Array.isArray(result)) {
    return result.map(item => serializeResult(item));
  }

  // Handle plain objects (recurse for nested models)
  if (typeof result === 'object' && result.constructor === Object) {
    const serialized = {};
    for (const [key, value] of Object.entries(result)) {
      serialized[key] = serializeResult(value);
    }
    return serialized;
  }

  return result;
}

/**
 * Generate a meta tag for CSRF token (for HTML responses)
 * @param {string} sessionId - Optional session ID
 * @returns {string} HTML meta tag
 */
export function csrfMetaTag(sessionId = '') {
  const token = getCSRF().generateToken(sessionId);
  return `<meta name="csrf-token" content="${token}">`;
}
