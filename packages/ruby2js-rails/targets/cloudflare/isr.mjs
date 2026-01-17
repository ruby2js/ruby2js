// Ruby2JS ISR (Incremental Static Regeneration) Adapter for Cloudflare Workers
//
// Uses Cloudflare's Cache API for edge caching with background regeneration
// via waitUntil(). Provides stale-while-revalidate behavior at the edge.
//
// Usage:
//   import { ISRCache } from 'ruby2js-rails/targets/cloudflare/isr.mjs';
//
//   export default {
//     async fetch(request, env, ctx) {
//       return ISRCache.serve({ request, env, ctx }, async (context) => {
//         const posts = await Post.all();
//         return renderPosts(posts);
//       }, { revalidate: 60 });
//     }
//   };

// Default revalidation time in seconds (1 minute)
const DEFAULT_REVALIDATE = 60;

// Default stale-while-revalidate window (24 hours)
const DEFAULT_STALE_WHILE_REVALIDATE = 86400;

/**
 * ISR Cache adapter for Cloudflare Workers.
 *
 * Uses Cloudflare's Cache API to store and retrieve responses at the edge.
 * Implements stale-while-revalidate pattern using waitUntil() for background
 * regeneration without blocking the response.
 *
 * @see https://developers.cloudflare.com/workers/runtime-apis/cache/
 */
export class ISRCache {
  /**
   * Serve content with ISR caching.
   *
   * @param {Object} context - Worker context
   * @param {Request} context.request - The incoming request
   * @param {Object} context.env - Worker environment bindings
   * @param {Object} context.ctx - Execution context with waitUntil
   * @param {Function} renderFn - Async function that renders content: (context) => Promise<string>
   * @param {Object} options - Caching options
   * @param {number} [options.revalidate=60] - Seconds until content is considered stale
   * @param {string} [options.cacheKey] - Custom cache key (defaults to request URL)
   * @param {Object} [options.headers={}] - Additional response headers
   * @returns {Promise<Response>} - Cached or freshly rendered response
   *
   * @example
   * // Basic usage
   * return ISRCache.serve({ request, env, ctx }, async () => {
   *   const posts = await Post.all();
   *   return `<ul>${posts.map(p => `<li>${p.title}</li>`).join('')}</ul>`;
   * }, { revalidate: 60 });
   *
   * @example
   * // With custom cache key
   * return ISRCache.serve({ request, env, ctx }, async (context) => {
   *   return renderPage(context);
   * }, { revalidate: 300, cacheKey: '/posts/all' });
   */
  static async serve(context, renderFn, options = {}) {
    const { request, ctx } = context;
    const revalidate = options.revalidate ?? DEFAULT_REVALIDATE;

    // Get the default cache
    const cache = caches.default;

    // Build cache key - use custom key or request URL
    const cacheKeyUrl = options.cacheKey
      ? new URL(options.cacheKey, request.url).href
      : request.url;
    const cacheKey = new Request(cacheKeyUrl, { method: 'GET' });

    // Check cache for existing response
    let response = await cache.match(cacheKey);

    if (response) {
      // Check if response is stale based on Age header
      const age = parseInt(response.headers.get('age') || '0', 10);
      const cacheTime = parseInt(response.headers.get('x-cache-time') || '0', 10);
      const now = Math.floor(Date.now() / 1000);
      const responseAge = cacheTime ? (now - cacheTime) : age;

      if (responseAge < revalidate) {
        // Fresh - serve from cache
        return this.addCacheHeaders(response.clone(), 'HIT', responseAge);
      }

      // Stale - serve stale content and regenerate in background
      if (ctx && ctx.waitUntil) {
        ctx.waitUntil(this.regenerate(context, cacheKey, renderFn, options));
      }
      return this.addCacheHeaders(response.clone(), 'STALE', responseAge);
    }

    // Cache miss - generate, cache, and serve
    return await this.regenerate(context, cacheKey, renderFn, options);
  }

  /**
   * Regenerate content and update cache.
   *
   * @param {Object} context - Worker context
   * @param {Request} cacheKey - Cache key request
   * @param {Function} renderFn - Render function
   * @param {Object} options - Caching options
   * @returns {Promise<Response>} - Fresh response
   */
  static async regenerate(context, cacheKey, renderFn, options = {}) {
    const { ctx } = context;
    const revalidate = options.revalidate ?? DEFAULT_REVALIDATE;
    const staleWhileRevalidate = options.staleWhileRevalidate ?? DEFAULT_STALE_WHILE_REVALIDATE;

    // Render fresh content
    const html = await renderFn(context);

    // Build response headers
    const headers = new Headers(options.headers || {});
    headers.set('Content-Type', 'text/html; charset=utf-8');
    headers.set('Cache-Control', `s-maxage=${revalidate}, stale-while-revalidate=${staleWhileRevalidate}`);
    headers.set('x-cache-time', String(Math.floor(Date.now() / 1000)));
    headers.set('x-cache-status', 'MISS');

    // Add cache tags if provided
    if (options.tags && Array.isArray(options.tags)) {
      headers.set('Cache-Tag', options.tags.join(','));
    }

    const response = new Response(html, {
      status: 200,
      headers,
    });

    // Store in cache (non-blocking)
    const cache = caches.default;
    if (ctx && ctx.waitUntil) {
      ctx.waitUntil(cache.put(cacheKey, response.clone()));
    } else {
      // Fallback: await the cache put
      await cache.put(cacheKey, response.clone());
    }

    return response;
  }

  /**
   * On-demand revalidation for a specific path.
   *
   * Deletes the cached response for the given path, forcing regeneration
   * on the next request.
   *
   * @param {string} path - The path to revalidate (full URL or path)
   * @param {Object} [options] - Options
   * @param {string} [options.baseUrl] - Base URL for relative paths
   * @returns {Promise<boolean>} - true if cache entry was deleted
   *
   * @example
   * // After updating a post
   * await ISRCache.revalidate('https://example.com/posts/123');
   *
   * @example
   * // With base URL
   * await ISRCache.revalidate('/posts/123', { baseUrl: 'https://example.com' });
   */
  static async revalidate(path, options = {}) {
    try {
      const cache = caches.default;

      // Build full URL if path is relative
      let url;
      if (path.startsWith('http://') || path.startsWith('https://')) {
        url = path;
      } else if (options.baseUrl) {
        url = new URL(path, options.baseUrl).href;
      } else {
        // Can't revalidate without knowing the full URL
        console.warn('ISRCache.revalidate: path must be a full URL or baseUrl must be provided');
        return false;
      }

      const cacheKey = new Request(url, { method: 'GET' });
      const deleted = await cache.delete(cacheKey);

      return deleted;
    } catch (error) {
      console.error('ISRCache.revalidate error:', error);
      return false;
    }
  }

  /**
   * Revalidate multiple paths at once.
   *
   * @param {string[]} paths - Array of paths to revalidate
   * @param {Object} [options] - Options (same as revalidate)
   * @returns {Promise<boolean[]>} - Array of results
   */
  static async revalidateMany(paths, options = {}) {
    return Promise.all(paths.map(path => this.revalidate(path, options)));
  }

  /**
   * Purge all cached content.
   *
   * Note: Cloudflare's Cache API doesn't support listing/purging all entries.
   * This method is provided for interface compatibility but has limited functionality.
   * Use Cloudflare's dashboard or API for full cache purging.
   *
   * @returns {Promise<boolean>} - Always returns false (not supported)
   */
  static async purgeAll() {
    console.warn('ISRCache.purgeAll: Not supported by Cloudflare Cache API. Use Cloudflare dashboard or API.');
    return false;
  }

  /**
   * Add cache status headers to response.
   *
   * @param {Response} response - Original response
   * @param {string} status - Cache status (HIT, MISS, STALE)
   * @param {number} [age] - Age in seconds
   * @returns {Response} - Response with cache headers
   */
  static addCacheHeaders(response, status, age) {
    const headers = new Headers(response.headers);
    headers.set('x-cache-status', status);
    if (age !== undefined) {
      headers.set('age', String(age));
    }

    return new Response(response.body, {
      status: response.status,
      statusText: response.statusText,
      headers,
    });
  }

  /**
   * Build Cache-Control header value.
   *
   * @param {Object} options - Caching options
   * @param {number} [options.revalidate] - s-maxage value
   * @param {number} [options.staleWhileRevalidate] - stale-while-revalidate value
   * @returns {string} - Cache-Control header value
   */
  static cacheControlHeader(options = {}) {
    const revalidate = options.revalidate ?? DEFAULT_REVALIDATE;
    const staleWhileRevalidate = options.staleWhileRevalidate ?? DEFAULT_STALE_WHILE_REVALIDATE;

    return `s-maxage=${revalidate}, stale-while-revalidate=${staleWhileRevalidate}`;
  }

  /**
   * Parse ISR options from pragma comments in source.
   *
   * @param {string[]} comments - Array of comment strings
   * @returns {Object|null} - Parsed options or null if no pragma found
   */
  static parsePragma(comments) {
    for (const comment of comments) {
      const match = comment.match(/Pragma:\s*revalidate\s+(\d+)/i);
      if (match) {
        return { revalidate: parseInt(match[1], 10) };
      }
    }
    return null;
  }

  /**
   * Extract route parameters from request URL.
   *
   * @param {Request} request - The incoming request
   * @returns {Object} - Extracted parameters
   */
  static extractParams(request) {
    const url = new URL(request.url);
    const params = {};

    for (const [key, value] of url.searchParams) {
      params[key] = value;
    }

    return params;
  }
}

// Export constants for external use
export { DEFAULT_REVALIDATE, DEFAULT_STALE_WHILE_REVALIDATE };
