// Ruby2JS ISR (Incremental Static Regeneration) Adapter for Vercel Edge
//
// Vercel Edge handles ISR automatically via Cache-Control headers.
// This adapter provides a simple interface that leverages Vercel's caching infrastructure.
//
// Usage:
//   import { ISRCache } from 'ruby2js-rails/targets/vercel-edge/isr.mjs';
//
//   export default async function handler(request) {
//     return ISRCache.serve(request, async (ctx) => {
//       const posts = await Post.all();
//       return renderPosts(posts);
//     }, { revalidate: 60 });
//   }

// Default revalidation time in seconds (1 minute)
const DEFAULT_REVALIDATE = 60;

// Default stale-while-revalidate window (24 hours)
const DEFAULT_STALE_WHILE_REVALIDATE = 86400;

/**
 * ISR Cache adapter for Vercel Edge Functions.
 *
 * Vercel Edge uses Cache-Control headers with s-maxage and stale-while-revalidate
 * directives. The Vercel CDN automatically handles:
 * - Caching responses at the edge
 * - Serving stale content while revalidating in the background
 * - Regional cache distribution
 *
 * @see https://vercel.com/docs/edge-network/caching
 */
export class ISRCache {
  /**
   * Serve content with ISR caching.
   *
   * @param {Request} request - The incoming request
   * @param {Function} renderFn - Async function that renders content: (context) => Promise<string>
   * @param {Object} options - Caching options
   * @param {number} [options.revalidate=60] - Seconds until content is considered stale
   * @param {number} [options.staleWhileRevalidate=86400] - Seconds to serve stale content while regenerating
   * @param {Object} [options.headers={}] - Additional response headers
   * @returns {Promise<Response>} - Response with caching headers
   *
   * @example
   * // Basic usage
   * return ISRCache.serve(request, async () => {
   *   const posts = await Post.all();
   *   return `<ul>${posts.map(p => `<li>${p.title}</li>`).join('')}</ul>`;
   * }, { revalidate: 60 });
   *
   * @example
   * // With context
   * return ISRCache.serve(request, async (ctx) => {
   *   const post = await Post.find(ctx.params.id);
   *   return renderPost(post);
   * }, { revalidate: 300 });
   */
  static async serve(request, renderFn, options = {}) {
    const revalidate = options.revalidate ?? DEFAULT_REVALIDATE;
    const staleWhileRevalidate = options.staleWhileRevalidate ?? DEFAULT_STALE_WHILE_REVALIDATE;

    // Create context from request
    const context = {
      request,
      url: new URL(request.url),
      params: this.extractParams(request),
    };

    // Render the content
    const html = await renderFn(context);

    // Build response headers
    const headers = new Headers(options.headers || {});
    headers.set('Content-Type', 'text/html; charset=utf-8');
    headers.set('Cache-Control', `s-maxage=${revalidate}, stale-while-revalidate=${staleWhileRevalidate}`);

    // Add cache tags if provided (Vercel supports cache tags for grouped invalidation)
    if (options.tags && Array.isArray(options.tags)) {
      headers.set('Cache-Tag', options.tags.join(','));
    }

    return new Response(html, {
      status: 200,
      headers,
    });
  }

  /**
   * On-demand revalidation for a specific path.
   *
   * Calls Vercel's revalidation API to invalidate cached content.
   * Requires VERCEL_TOKEN environment variable.
   *
   * @param {string} path - The path to revalidate (e.g., '/posts/123')
   * @param {Object} [options] - Revalidation options
   * @param {string} [options.token] - Vercel API token (defaults to process.env.VERCEL_TOKEN)
   * @param {string} [options.teamId] - Vercel team ID (optional)
   * @param {string} [options.projectId] - Vercel project ID (optional, defaults to process.env.VERCEL_PROJECT_ID)
   * @returns {Promise<boolean>} - true if revalidation was successful
   *
   * @example
   * // After updating a post
   * await ISRCache.revalidate('/posts/123');
   *
   * @example
   * // With explicit token
   * await ISRCache.revalidate('/posts', { token: 'vercel_xxx' });
   */
  static async revalidate(path, options = {}) {
    const token = options.token || process.env.VERCEL_TOKEN;
    const projectId = options.projectId || process.env.VERCEL_PROJECT_ID;

    if (!token) {
      console.warn('ISRCache.revalidate: VERCEL_TOKEN not set, skipping revalidation');
      return false;
    }

    try {
      // Vercel's on-demand revalidation API
      // Note: The exact API endpoint may vary based on your Vercel setup
      // This uses the general purge endpoint
      const url = new URL('https://api.vercel.com/v1/edge-config/purge');

      // Add query parameters
      if (projectId) url.searchParams.set('projectId', projectId);
      if (options.teamId) url.searchParams.set('teamId', options.teamId);
      url.searchParams.set('path', path);

      const response = await fetch(url.toString(), {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
      });

      if (!response.ok) {
        const error = await response.text();
        console.error(`ISRCache.revalidate failed: ${response.status} ${error}`);
        return false;
      }

      return true;
    } catch (error) {
      console.error('ISRCache.revalidate error:', error);
      return false;
    }
  }

  /**
   * Revalidate by cache tag.
   *
   * Vercel supports cache tags for grouped invalidation.
   * All responses with the specified tag will be revalidated.
   *
   * @param {string} tag - The cache tag to revalidate
   * @param {Object} [options] - Same options as revalidate()
   * @returns {Promise<boolean>} - true if revalidation was successful
   *
   * @example
   * // Invalidate all posts
   * await ISRCache.revalidateTag('posts');
   */
  static async revalidateTag(tag, options = {}) {
    const token = options.token || process.env.VERCEL_TOKEN;
    const projectId = options.projectId || process.env.VERCEL_PROJECT_ID;

    if (!token) {
      console.warn('ISRCache.revalidateTag: VERCEL_TOKEN not set, skipping revalidation');
      return false;
    }

    try {
      const url = new URL('https://api.vercel.com/v1/edge-config/purge');

      if (projectId) url.searchParams.set('projectId', projectId);
      if (options.teamId) url.searchParams.set('teamId', options.teamId);
      url.searchParams.set('tag', tag);

      const response = await fetch(url.toString(), {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
      });

      if (!response.ok) {
        const error = await response.text();
        console.error(`ISRCache.revalidateTag failed: ${response.status} ${error}`);
        return false;
      }

      return true;
    } catch (error) {
      console.error('ISRCache.revalidateTag error:', error);
      return false;
    }
  }

  /**
   * Extract route parameters from request.
   * Override this method for custom parameter extraction.
   *
   * @param {Request} request - The incoming request
   * @returns {Object} - Extracted parameters
   */
  static extractParams(request) {
    const url = new URL(request.url);
    const params = {};

    // Extract query parameters
    for (const [key, value] of url.searchParams) {
      params[key] = value;
    }

    return params;
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
}

// Export constants for external use
export { DEFAULT_REVALIDATE, DEFAULT_STALE_WHILE_REVALIDATE };
