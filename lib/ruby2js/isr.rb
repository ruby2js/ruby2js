module Ruby2JS
  # ISR (Incremental Static Regeneration) adapter interface.
  #
  # ISR enables pages to be statically generated at runtime and cached,
  # with automatic background regeneration when stale. This provides the
  # performance of static sites with the freshness of dynamic content.
  #
  # Platform-specific adapters (Vercel, Cloudflare) implement this interface
  # to leverage each platform's caching infrastructure.
  #
  # == Usage in pages
  #
  # Use the revalidate pragma to enable ISR for a page:
  #
  #   # Pragma: revalidate 60
  #
  #   @posts = Post.all
  #   __END__
  #   <ul>
  #     <% @posts.each do |post| %>
  #       <li><%= post.title %></li>
  #     <% end %>
  #   </ul>
  #
  # The page will be cached for 60 seconds, then regenerated in the background
  # while serving stale content.
  #
  # == Implementing an adapter
  #
  #   class MyPlatformISR < Ruby2JS::ISR::Base
  #     def self.serve(context, cache_key, options = {}, &block)
  #       # Check cache, serve if fresh
  #       # If stale, serve stale and regenerate in background
  #       # If miss, generate, cache, and serve
  #     end
  #
  #     def self.revalidate(path)
  #       # Invalidate cache for the given path
  #     end
  #   end
  #
  module ISR
    # Default revalidation time in seconds (1 minute)
    DEFAULT_REVALIDATE = 60

    # Default stale-while-revalidate window (24 hours)
    DEFAULT_STALE_WHILE_REVALIDATE = 86400

    # Base class for ISR adapters.
    #
    # Platform-specific adapters should inherit from this class and implement
    # the +serve+ and +revalidate+ methods.
    #
    class Base
      # Serve content with ISR caching.
      #
      # @param context [Object] Request context (platform-specific)
      # @param cache_key [String] Cache key, typically the URL path
      # @param options [Hash] Caching options
      # @option options [Integer] :revalidate Seconds until content is stale (default: 60)
      # @option options [Integer] :stale_while_revalidate Seconds to serve stale content
      #   while regenerating (default: 86400)
      # @option options [Hash] :tags Cache tags for grouped invalidation
      # @yield Block that renders the content
      # @yieldparam context [Object] The request context
      # @yieldreturn [String] The rendered HTML content
      # @return [Object] Platform-specific response object
      #
      # @example
      #   ISRAdapter.serve(request, '/posts', revalidate: 60) do |ctx|
      #     render_posts_page(ctx)
      #   end
      #
      def self.serve(context, cache_key, options = {}, &block)
        raise NotImplementedError, "#{name}.serve must be implemented by subclass"
      end

      # Invalidate cached content for a path.
      #
      # Use this for on-demand revalidation when content changes, rather than
      # waiting for the revalidation window.
      #
      # @param path [String] The path to invalidate
      # @return [Boolean] true if invalidation was successful
      #
      # @example
      #   # After updating a post
      #   ISRAdapter.revalidate('/posts')
      #   ISRAdapter.revalidate("/posts/#{post.id}")
      #
      def self.revalidate(path)
        raise NotImplementedError, "#{name}.revalidate must be implemented by subclass"
      end

      # Invalidate cached content by tag.
      #
      # Some platforms support cache tags for grouped invalidation.
      # This is optional - adapters that don't support tags can skip this.
      #
      # @param tag [String] The cache tag to invalidate
      # @return [Boolean] true if invalidation was successful
      #
      # @example
      #   # Invalidate all posts-related caches
      #   ISRAdapter.revalidate_tag('posts')
      #
      def self.revalidate_tag(tag)
        raise NotImplementedError, "#{name}.revalidate_tag is not supported"
      end

      # Parse ISR options from pragma comments.
      #
      # @param comments [Array<String>] Comment lines from source
      # @return [Hash, nil] Parsed options or nil if no ISR pragma found
      #
      # @example
      #   parse_pragma(['# Pragma: revalidate 60'])
      #   # => { revalidate: 60 }
      #
      def self.parse_pragma(comments)
        comments.each do |comment|
          text = comment.is_a?(String) ? comment : comment.to_s
          if text =~ /Pragma:\s*revalidate\s+(\d+)/i
            return { revalidate: $1.to_i }
          end
        end
        nil
      end

      # Build Cache-Control header value for ISR.
      #
      # @param options [Hash] ISR options
      # @option options [Integer] :revalidate Seconds until stale
      # @option options [Integer] :stale_while_revalidate Stale serve window
      # @return [String] Cache-Control header value
      #
      def self.cache_control_header(options = {})
        revalidate = options[:revalidate] || DEFAULT_REVALIDATE
        stale_window = options[:stale_while_revalidate] || DEFAULT_STALE_WHILE_REVALIDATE

        "s-maxage=#{revalidate}, stale-while-revalidate=#{stale_window}"
      end
    end

    # In-memory ISR adapter for development and testing.
    #
    # This adapter provides a simple in-memory cache that mimics ISR behavior
    # without requiring a platform-specific caching layer.
    #
    # NOT suitable for production use - cache is not shared across processes
    # and has no size limits.
    #
    class Memory < Base
      @cache = {}
      @cache_times = {}

      class << self
        # Clear the in-memory cache (useful for testing)
        def clear_cache
          @cache = {}
          @cache_times = {}
        end

        def serve(context, cache_key, options = {}, &block)
          revalidate = options[:revalidate] || DEFAULT_REVALIDATE
          now = Time.now.to_i

          cached = @cache[cache_key]
          cached_time = @cache_times[cache_key]

          if cached && cached_time
            age = now - cached_time
            if age < revalidate
              # Fresh - serve from cache
              return cached
            else
              # Stale - serve stale and regenerate
              # In a real adapter, regeneration would happen in background
              # For memory adapter, we regenerate synchronously
              content = block.call(context)
              @cache[cache_key] = content
              @cache_times[cache_key] = now
              return cached  # Return stale content (simulating async regeneration)
            end
          end

          # Cache miss - generate and cache
          content = block.call(context)
          @cache[cache_key] = content
          @cache_times[cache_key] = now
          content
        end

        def revalidate(path)
          @cache.delete(path)
          @cache_times.delete(path)
          true
        end

        def revalidate_tag(tag)
          # Memory adapter doesn't support tags - clear everything
          clear_cache
          true
        end
      end
    end
  end
end
