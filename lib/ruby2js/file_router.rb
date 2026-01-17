module Ruby2JS
  # FileRouter discovers routes from filesystem conventions (Next.js/SvelteKit style).
  # Routes are derived from files in the pages directory:
  #
  #   app/pages/
  #     index.rb           → /
  #     about.rb           → /about
  #     blog/
  #       index.rb         → /blog
  #       [slug].rb        → /blog/:slug
  #       [...rest].rb     → /blog/*rest
  #
  # File-based routes can be merged with explicit routes from config/routes.rb,
  # with explicit routes taking precedence.
  #
  class FileRouter
    attr_reader :pages_dir, :routes

    # Supported file extensions for pages (longer extensions first for proper matching)
    EXTENSIONS = %w[.jsx.rb .vue.rb .svelte.rb .erb.rb .rb].freeze

    def initialize(pages_dir)
      @pages_dir = pages_dir.to_s.chomp('/')
      @routes = []
    end

    # Discover routes from the pages directory
    # Returns array of route hashes: { file:, path:, dynamic_segments: }
    def discover
      @routes = []
      return @routes unless File.directory?(@pages_dir)

      # Find all page files
      pattern = File.join(@pages_dir, '**', '*')
      Dir.glob(pattern).each do |file|
        next unless File.file?(file)
        next unless page_file?(file)

        route = file_to_route(file)
        @routes << route if route
      end

      # Sort routes: static routes before dynamic, shorter before longer
      @routes.sort_by! { |r| route_sort_key(r) }

      @routes
    end

    # Convert a file path to a route configuration
    def file_to_route(file)
      # Get path relative to pages_dir, remove extension
      relative = file.sub("#{@pages_dir}/", '')
      relative = remove_extension(relative)

      # Convert to route path
      path = relative
        .gsub(/\/?index$/, '')          # index.rb → /, blog/index.rb → /blog
        .gsub(/\[\.\.\.(\w+)\]/, '*\1') # [...rest] → *rest (catch-all)
        .gsub(/\[(\w+)\]/, ':\1')       # [slug] → :slug (dynamic segment)

      path = '/' if path.empty?
      path = "/#{path}" unless path.start_with?('/')

      # Extract dynamic segment names
      dynamic_segments = []
      path.scan(/:(\w+)/) { |m| dynamic_segments << m[0].to_sym }
      path.scan(/\*(\w+)/) { |m| dynamic_segments << :"*#{m[0]}" }

      {
        file: file,
        path: path,
        dynamic_segments: dynamic_segments
      }
    end

    # Merge file-based routes with explicit routes.
    # Explicit routes take precedence (overwrite file-based routes with same path).
    #
    # @param explicit_routes [Array<Hash>] Routes from config/routes.rb
    # @return [Array<Hash>] Merged routes with explicit routes taking precedence
    def merge_with(explicit_routes)
      # Index file-based routes by path
      routes_by_path = {}
      @routes.each { |r| routes_by_path[r[:path]] = r }

      # Overlay explicit routes (they win on conflict)
      explicit_routes.each { |r| routes_by_path[r[:path]] = r }

      # Return sorted routes
      routes_by_path.values.sort_by { |r| route_sort_key(r) }
    end

    # Class method for convenient one-liner usage
    def self.discover(pages_dir)
      new(pages_dir).tap(&:discover).routes
    end

    # Class method to discover and merge with explicit routes
    def self.discover_and_merge(pages_dir, explicit_routes)
      router = new(pages_dir)
      router.discover
      router.merge_with(explicit_routes)
    end

    private

    # Check if file is a page file (has supported extension)
    def page_file?(file)
      EXTENSIONS.any? { |ext| file.end_with?(ext) }
    end

    # Remove page file extension
    def remove_extension(path)
      EXTENSIONS.each do |ext|
        return path[0..-(ext.length + 1)] if path.end_with?(ext)
      end
      path
    end

    # Generate sort key for route ordering
    # Static routes before dynamic, shorter before longer, alphabetical
    def route_sort_key(route)
      path = route[:path]
      [
        path.include?('*') ? 1 : 0,  # Catch-all routes last
        path.include?(':') ? 1 : 0,  # Dynamic routes after static
        path.count('/'),              # Shorter paths first
        path                          # Alphabetical
      ]
    end
  end
end
