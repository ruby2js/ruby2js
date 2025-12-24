# frozen_string_literal: true

module Ruby2JS
  module Spa
    # Rack middleware to serve the SPA at its mount path
    #
    # For any request starting with the mount_path, serves:
    # - Static assets (JS, CSS) directly
    # - index.html for all other paths (client-side routing)
    #
    class Middleware
      def initialize(app, options = {})
        @app = app
        @mount_path = options[:mount_path] || '/offline'
        @spa_root = options[:spa_root]&.to_s
      end

      def call(env)
        path = env['PATH_INFO']

        if path.start_with?(@mount_path) && @spa_root && Dir.exist?(@spa_root)
          serve_spa(env, path)
        else
          @app.call(env)
        end
      end

      private

      def serve_spa(env, path)
        # Remove mount path prefix to get the relative path
        relative_path = path.sub(@mount_path, '').sub(%r{^/}, '')

        # Try to serve static file first
        if relative_path.match?(/\.(js|css|map|json|wasm|png|jpg|svg|ico)$/)
          static_file = File.join(@spa_root, relative_path)
          if File.exist?(static_file)
            return serve_file(static_file)
          end
        end

        # For all other paths, serve index.html (client-side routing)
        index_file = File.join(@spa_root, 'index.html')
        if File.exist?(index_file)
          serve_file(index_file)
        else
          [404, { 'Content-Type' => 'text/plain' }, ['SPA not found. Run: rake ruby2js:spa:build']]
        end
      end

      def serve_file(path)
        content = File.read(path)
        content_type = mime_type(path)
        [200, { 'Content-Type' => content_type, 'Content-Length' => content.bytesize.to_s }, [content]]
      end

      def mime_type(path)
        case File.extname(path).downcase
        when '.html' then 'text/html; charset=utf-8'
        when '.js', '.mjs' then 'application/javascript; charset=utf-8'
        when '.css' then 'text/css; charset=utf-8'
        when '.json' then 'application/json; charset=utf-8'
        when '.map' then 'application/json; charset=utf-8'
        when '.wasm' then 'application/wasm'
        when '.png' then 'image/png'
        when '.jpg', '.jpeg' then 'image/jpeg'
        when '.svg' then 'image/svg+xml'
        when '.ico' then 'image/x-icon'
        else 'application/octet-stream'
        end
      end
    end
  end
end
