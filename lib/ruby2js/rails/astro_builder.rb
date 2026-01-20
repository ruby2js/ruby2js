# frozen_string_literal: true

require 'fileutils'
require 'json'
require_relative 'erb_to_astro'

module Ruby2JS
  module Rails
    # Builds a complete Astro project from a Rails application.
    #
    # Converts Rails ERB views, controllers, and models to an Astro project
    # that can run in the browser (IndexedDB) or edge (D1).
    #
    # Usage:
    #   AstroBuilder.new(options).build
    #
    class AstroBuilder
      DIST_DIR = 'dist'

      def initialize(options = {})
        @options = options
        @verbose = options[:verbose]
        @database = options[:database] || ENV['JUNTOS_DATABASE'] || 'dexie'
        @app_name = detect_app_name
      end

      def build
        log "Converting Rails app to Astro..."

        setup_output_directories
        generate_project_files
        generate_browser_adapter
        generate_astro_config
        generate_layout
        convert_views
        convert_partials
        copy_models
        generate_database_setup
        generate_seeds
        generate_browser_shell
        generate_bundler
        copy_assets
        install_dependencies
        run_build

        log "Astro conversion complete."
        log ""
        log "To preview:"
        log "  cd #{DIST_DIR} && npm run preview"
        true
      rescue => e
        warn "Error: #{e.message}"
        warn e.backtrace.first(10).join("\n") if @verbose
        false
      end

      private

      def log(message)
        puts message if @verbose || !@options[:quiet]
      end

      def detect_app_name
        if File.exist?('config/application.rb')
          content = File.read('config/application.rb')
          if content =~ /module\s+(\w+)/
            return $1.gsub(/([a-z])([A-Z])/, '\1-\2').downcase
          end
        end
        File.basename(Dir.pwd).downcase.gsub(/[^a-z0-9]/, '-')
      end

      def setup_output_directories
        FileUtils.rm_rf(DIST_DIR)
        FileUtils.mkdir_p(File.join(DIST_DIR, 'src', 'pages'))
        FileUtils.mkdir_p(File.join(DIST_DIR, 'src', 'components'))
        FileUtils.mkdir_p(File.join(DIST_DIR, 'src', 'layouts'))
        FileUtils.mkdir_p(File.join(DIST_DIR, 'src', 'lib'))
        FileUtils.mkdir_p(File.join(DIST_DIR, 'src', 'models'))
        FileUtils.mkdir_p(File.join(DIST_DIR, 'public'))
      end

      def generate_project_files
        log "  Generating project files..."

        # package.json
        package = {
          "name" => "#{@app_name}-astro",
          "version" => "0.0.1",
          "type" => "module",
          "scripts" => {
            "dev" => "astro dev",
            "build" => "astro build && node bundle-for-browser.mjs",
            "preview" => "npx serve dist/client"
          },
          "dependencies" => {
            "astro" => "^5.0.0",
            "@hotwired/turbo" => "^8.0.0"
          },
          "devDependencies" => {
            "esbuild" => "^0.24.0"
          }
        }
        File.write(File.join(DIST_DIR, 'package.json'), JSON.pretty_generate(package) + "\n")

        # tsconfig.json
        tsconfig = {
          "extends" => "astro/tsconfigs/strict",
          "compilerOptions" => {
            "strictNullChecks" => true
          }
        }
        File.write(File.join(DIST_DIR, 'tsconfig.json'), JSON.pretty_generate(tsconfig) + "\n")
      end

      def generate_browser_adapter
        log "  Generating browser adapter..."

        adapter = <<~JS
          // Minimal browser adapter for Astro
          // Produces a worker-like module with fetch(request) -> Response

          export default function browserAdapter() {
            return {
              name: 'astro-adapter-browser',
              hooks: {
                'astro:config:done': ({ setAdapter }) => {
                  setAdapter({
                    name: 'astro-adapter-browser',
                    serverEntrypoint: './browser-server.mjs',
                    exports: ['default'],
                    adapterFeatures: {
                      buildOutput: 'server'
                    },
                    supportedAstroFeatures: {
                      serverOutput: 'stable',
                      staticOutput: 'stable'
                    }
                  });
                }
              }
            };
          }
        JS
        File.write(File.join(DIST_DIR, 'browser-adapter.mjs'), adapter)

        server = <<~JS
          // Browser server runtime - exports a fetch handler
          import { App } from 'astro/app';

          export function createExports(manifest) {
            const app = new App(manifest);

            return {
              default: {
                async fetch(request, env, ctx) {
                  const response = await app.render(request);
                  return response;
                }
              }
            };
          }

          export function start(manifest) {
            // No-op for browser - we don't auto-start
          }
        JS
        File.write(File.join(DIST_DIR, 'browser-server.mjs'), server)
      end

      def generate_astro_config
        log "  Generating Astro config..."

        config = <<~JS
          import { defineConfig } from 'astro/config';
          import browserAdapter from './browser-adapter.mjs';
          import { ruby2jsModels } from 'ruby2js-rails/vite-models';

          export default defineConfig({
            output: 'server',
            adapter: browserAdapter(),
            security: {
              checkOrigin: false
            },
            image: {
              service: { entrypoint: 'astro/assets/services/noop' }
            },
            vite: {
              plugins: [
                ruby2jsModels({
                  database: '#{@database}',
                  modelsDir: 'src/models',
                  outDir: 'src/lib/models'
                })
              ]
            }
          });
        JS
        File.write(File.join(DIST_DIR, 'astro.config.mjs'), config)
      end

      def generate_layout
        log "  Generating layout..."

        # Check for Rails layout
        rails_layout = 'app/views/layouts/application.html.erb'

        layout = <<~ASTRO
          ---
          interface Props {
            title: string;
          }

          const { title } = Astro.props;
          ---

          <!doctype html>
          <html lang="en">
            <head>
              <meta charset="UTF-8" />
              <meta name="viewport" content="width=device-width" />
              <title>{title}</title>
              <style>
                :root {
                  --color-bg: #f9fafb;
                  --color-text: #111827;
                  --color-primary: #2563eb;
                  --color-primary-dark: #1d4ed8;
                  --color-border: #e5e7eb;
                  --color-error: #dc2626;
                  --max-width: 800px;
                }

                * { box-sizing: border-box; margin: 0; padding: 0; }

                body {
                  font-family: system-ui, -apple-system, sans-serif;
                  background: var(--color-bg);
                  color: var(--color-text);
                  line-height: 1.6;
                  padding: 2rem;
                }

                .container { max-width: var(--max-width); margin: 0 auto; }

                header {
                  margin-bottom: 2rem;
                  padding-bottom: 1rem;
                  border-bottom: 1px solid var(--color-border);
                }

                header h1 a { color: var(--color-text); text-decoration: none; }

                nav { margin-top: 0.5rem; }
                nav a { color: var(--color-primary); text-decoration: none; margin-right: 1rem; }
                nav a:hover { text-decoration: underline; }

                .btn {
                  display: inline-block;
                  padding: 0.5rem 1rem;
                  background: var(--color-primary);
                  color: white;
                  text-decoration: none;
                  border: none;
                  border-radius: 4px;
                  cursor: pointer;
                }
                .btn:hover { background: var(--color-primary-dark); }
                .btn-danger { background: var(--color-error); }

                .form-group { margin-bottom: 1rem; }
                .form-group label { display: block; margin-bottom: 0.25rem; font-weight: 500; }
                .form-group input, .form-group textarea {
                  width: 100%;
                  padding: 0.5rem;
                  border: 1px solid var(--color-border);
                  border-radius: 4px;
                }

                .article-card {
                  background: white;
                  padding: 1rem;
                  margin-bottom: 1rem;
                  border-radius: 8px;
                  border: 1px solid var(--color-border);
                }
                .article-card h2 a { color: var(--color-text); text-decoration: none; }
                .article-card h2 a:hover { color: var(--color-primary); }

                .article-meta { color: #666; font-size: 0.875rem; margin: 0.5rem 0; }

                .actions { margin: 1rem 0; display: flex; gap: 0.5rem; align-items: center; }

                .comment { background: #f3f4f6; padding: 1rem; margin-bottom: 0.5rem; border-radius: 4px; }
                .comment-meta { font-size: 0.875rem; color: #666; }

                .error-messages {
                  background: #fef2f2;
                  border: 1px solid var(--color-error);
                  color: var(--color-error);
                  padding: 1rem;
                  border-radius: 4px;
                  margin-bottom: 1rem;
                }
                .error-messages ul { margin: 0; padding-left: 1.5rem; }
              </style>
            </head>
            <body>
              <div class="container">
                <header>
                  <h1><a href="/">#{@app_name.capitalize}</a></h1>
                  <nav>
                    <a href="/">Home</a>
                    <a href="/articles">Articles</a>
                  </nav>
                </header>
                <main>
                  <slot />
                </main>
              </div>
            </body>
          </html>
        ASTRO
        File.write(File.join(DIST_DIR, 'src', 'layouts', 'Layout.astro'), layout)
      end

      def convert_views
        log "  Converting views..."

        # Find all view directories (each represents a controller)
        view_dirs = Dir.glob('app/views/*').select { |f| File.directory?(f) }

        view_dirs.each do |view_dir|
          controller_name = File.basename(view_dir)
          next if controller_name == 'layouts' # Skip layouts directory

          convert_controller_views(controller_name, view_dir)
        end
      end

      def convert_controller_views(controller_name, view_dir)
        controller_file = "app/controllers/#{controller_name}_controller.rb"
        controller_code = File.exist?(controller_file) ? File.read(controller_file) : nil

        # Find all non-partial ERB files
        erb_files = Dir.glob(File.join(view_dir, '*.html.erb')).reject { |f| File.basename(f).start_with?('_') }

        erb_files.each do |erb_file|
          action_name = File.basename(erb_file, '.html.erb')
          convert_view(controller_name, action_name, erb_file, controller_code)
        end
      end

      def convert_view(controller_name, action_name, erb_file, controller_code)
        log "    #{controller_name}/#{action_name}..."

        erb_content = File.read(erb_file)
        action_code = extract_action(controller_code, action_name) if controller_code

        astro_content = ErbToAstro.convert(
          erb: erb_content,
          action: action_code,
          controller: controller_name,
          action_name: action_name,
          options: @options
        )

        # Determine output path
        output_path = case action_name
        when 'index'
          File.join(DIST_DIR, 'src', 'pages', controller_name, 'index.astro')
        when 'show'
          File.join(DIST_DIR, 'src', 'pages', controller_name, '[id].astro')
        when 'edit'
          File.join(DIST_DIR, 'src', 'pages', controller_name, '[id]', 'edit.astro')
        when 'new'
          File.join(DIST_DIR, 'src', 'pages', controller_name, 'new.astro')
        else
          File.join(DIST_DIR, 'src', 'pages', controller_name, "#{action_name}.astro")
        end

        FileUtils.mkdir_p(File.dirname(output_path))
        File.write(output_path, astro_content)
      end

      def convert_partials
        log "  Converting partials..."

        # Find all partial ERB files across all view directories
        partial_files = Dir.glob('app/views/**/_*.html.erb')

        partial_files.each do |partial_file|
          convert_partial(partial_file)
        end
      end

      def convert_partial(partial_file)
        partial_name = File.basename(partial_file, '.html.erb').sub(/^_/, '')
        log "    _#{partial_name}..."

        erb_content = File.read(partial_file)

        # Get the controller/model name from directory path
        dir_name = File.basename(File.dirname(partial_file))
        model_name = dir_name.end_with?('s') ? dir_name[0..-2] : dir_name

        # Determine component name
        base_component = partial_name.split('_').map(&:capitalize).join
        component_name = partial_name.end_with?('form') ? base_component : "#{base_component}Card"

        astro_content = convert_partial_to_component(erb_content, partial_name, model_name, component_name)

        output_path = File.join(DIST_DIR, 'src', 'components', "#{component_name}.astro")
        File.write(output_path, astro_content)
      end

      def convert_partial_to_component(erb_content, partial_name, model_name, component_name)
        converter = PartialConverter.new(erb_content, partial_name, model_name, @options)
        converter.convert
      end

      def copy_models
        log "  Copying models..."

        model_files = Dir.glob('app/models/*.rb').reject { |f| File.basename(f) == 'application_record.rb' }

        model_files.each do |model_file|
          dest = File.join(DIST_DIR, 'src', 'models', File.basename(model_file))
          FileUtils.cp(model_file, dest)
          log "    #{File.basename(model_file)}"
        end
      end

      def generate_database_setup
        log "  Generating database setup..."

        # Detect model names and their associations from app/models
        model_files = Dir.glob('app/models/*.rb')
          .reject { |f| File.basename(f) == 'application_record.rb' }

        # Generate Dexie schema registrations with proper indexes
        schema_registrations = model_files.map do |model_file|
          model = File.basename(model_file, '.rb')
          table = model.end_with?('s') ? model : "#{model}s"

          # Detect belongs_to associations for foreign key indexes
          content = File.read(model_file)
          foreign_keys = content.scan(/belongs_to\s+:(\w+)/).flatten
          indexes = ['++id'] + foreign_keys.map { |fk| "#{fk}_id" } + ['created_at']

          "registerSchema('#{table}', '#{indexes.join(', ')}');"
        end.join("\n")

        db_mjs = <<~JS
          // Database setup - uses Dexie adapter for IndexedDB
          import {
            initDatabase,
            openDatabase,
            defineSchema,
            registerSchema
          } from 'ruby2js-rails/adapters/active_record_dexie.mjs';
          import { runSeeds } from './seeds.mjs';

          let initialized = false;

          // Register schemas for Dexie
          #{schema_registrations}

          export async function setupDatabase() {
            if (initialized) return;

            await initDatabase({ database: '#{@app_name}' });
            defineSchema(1);
            await openDatabase();

            // Run seeds if database is empty
            await runSeeds();

            initialized = true;
          }

          export { initDatabase, openDatabase, defineSchema, registerSchema };
        JS
        File.write(File.join(DIST_DIR, 'src', 'lib', 'db.mjs'), db_mjs)
      end

      def generate_seeds
        log "  Generating seeds..."

        # Detect models for import
        models = Dir.glob('app/models/*.rb')
          .map { |f| File.basename(f, '.rb') }
          .reject { |n| n == 'application_record' }
          .map { |n| n.split('_').map(&:capitalize).join }

        imports = models.empty? ? '' : "import { #{models.join(', ')} } from './models/index.js';"
        first_model = models.first || 'Article'

        # Check for Rails seeds file
        rails_seeds = 'db/seeds.rb'
        seed_body = nil

        if File.exist?(rails_seeds)
          seed_body = transpile_seeds(File.read(rails_seeds), first_model)
          if seed_body
            log "    Transpiled db/seeds.rb"
          else
            log "    (Rails seeds found, transpilation failed - using placeholder)"
          end
        end

        # Fallback placeholder if no seeds or transpilation failed
        seed_body ||= <<~JS.strip
            // TODO: Add seed data here
            // Example:
            // await Article.create({ title: 'Hello World', body: 'Welcome to the app!' });
        JS

        seeds_mjs = <<~JS
          // Sample data for the application
          // Seeds are idempotent - only run if database is empty
          #{imports}

          export async function runSeeds() {
            // Check if already seeded
            const count = await #{first_model}.count();
            if (count > 0) return;

            console.log('Seeding database...');

          #{seed_body}

            const articleCount = await Article.count();
            const commentCount = await Comment.count();
            console.log(`Seeded ${articleCount} articles and ${commentCount} comments`);
          }
        JS
        File.write(File.join(DIST_DIR, 'src', 'lib', 'seeds.mjs'), seeds_mjs)
      end

      def transpile_seeds(ruby_code, first_model)
        # Remove the idempotency guard (we handle it in the wrapper)
        ruby_code = ruby_code.gsub(/^return if #{first_model}\.count > 0\s*\n?/, '')

        # Remove puts statements (we handle logging in the wrapper)
        ruby_code = ruby_code.gsub(/^puts .*\n?/, '')

        # Transform seeds to async JavaScript
        begin
          js = Ruby2JS.convert(ruby_code, filters: [:functions, :esm, :return]).to_s

          # Post-process for async/await patterns
          # IMPORTANT: Handle association creates FIRST (before general Model.create)

          # article.comments.create({...}) -> Comment.create({ article_id: article.id, ... })
          # Note: Don't add await here - the Model.create regex below will add it
          js = js.gsub(/(\w+)\.comments\.create!?\(\{([^}]+)\}\)/) do
            parent_var = $1
            attrs = $2
            "Comment.create({ article_id: #{parent_var}.id, #{attrs} })"
          end

          # Model.create!({...}) -> await Model.create({...})
          # Only match capitalized model names to avoid matching method chains
          js = js.gsub(/([A-Z]\w*)\.create!?\(/, 'await \1.create(')

          # Indent the result
          js.lines.map { |line| "  #{line}" }.join
        rescue => e
          nil
        end
      end

      def generate_browser_shell
        log "  Generating browser shell..."

        index_html = <<~HTML
          <!DOCTYPE html>
          <html>
          <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>#{@app_name.capitalize}</title>
          </head>
          <body>
            <div id="app">Loading...</div>
            <script type="module">
              // Load Turbo from CDN
              import * as Turbo from 'https://esm.sh/@hotwired/turbo@8';

              // Minimal shim for process.env
              window.process = { env: {} };

              // TurboBroadcast for cross-tab real-time updates
              // Note: We use native BroadcastChannel internally, but expose as TurboBroadcast
              // to avoid conflicting with Dexie's use of BroadcastChannel
              class TurboBroadcast {
                static channels = new Map();

                static getChannel(name) {
                  if (!this.channels.has(name)) {
                    const channel = new BroadcastChannel(name);
                    channel.onmessage = (event) => {
                      if (event.data && event.data.includes('<turbo-stream')) {
                        Turbo.renderStreamMessage(event.data);
                      }
                    };
                    this.channels.set(name, channel);
                  }
                  return this.channels.get(name);
                }

                static broadcast(channelName, html) {
                  if (typeof html !== 'string') {
                    console.warn('TurboBroadcast: html is not a string:', typeof html, html);
                    return;
                  }
                  const channel = this.getChannel(channelName);
                  channel.postMessage(html);
                  if (html.includes('<turbo-stream')) {
                    Turbo.renderStreamMessage(html);
                  }
                }

                static subscribe(channelName) {
                  this.getChannel(channelName);
                  return '';
                }

                static unsubscribe(channelName) {
                  const channel = this.channels.get(channelName);
                  if (channel) {
                    channel.close();
                    this.channels.delete(channelName);
                  }
                }
              }

              // Make TurboBroadcast available globally for models
              // Note: We use TurboBroadcast name, NOT BroadcastChannel, because Dexie needs native BroadcastChannel
              window.TurboBroadcast = TurboBroadcast;
              globalThis.TurboBroadcast = TurboBroadcast;

              const app = document.getElementById('app');
              let worker;
              let activeSubscriptions = new Set();

              async function init() {
                worker = await import('/browser-worker.mjs');
                await navigate(location.pathname || '/');
              }

              async function navigate(path) {
                const url = new URL(path, location.origin);
                const request = new Request(url.href);

                try {
                  const response = await worker.default.fetch(request);
                  const html = await response.text();

                  const parser = new DOMParser();
                  const doc = parser.parseFromString(html, 'text/html');

                  const title = doc.querySelector('title');
                  if (title) document.title = title.textContent;

                  document.body.innerHTML = doc.body.innerHTML;
                  attachLinkHandlers();
                  updateSubscriptions(path);
                } catch (e) {
                  app.innerHTML = '<p style="color:red">Error: ' + e.message + '</p>';
                  console.error(e);
                }
              }

              function updateSubscriptions(path) {
                for (const channel of activeSubscriptions) {
                  TurboBroadcast.unsubscribe(channel);
                }
                activeSubscriptions.clear();

                // Subscribe based on current path
                if (path.match(/^\\/articles\\/?$/)) {
                  TurboBroadcast.subscribe('articles');
                  activeSubscriptions.add('articles');
                } else if (path.match(/^\\/articles\\/(\\d+)$/)) {
                  const articleId = path.match(/^\\/articles\\/(\\d+)$/)[1];
                  const channel = `article_${articleId}_comments`;
                  TurboBroadcast.subscribe(channel);
                  activeSubscriptions.add(channel);
                }
              }

              async function submitForm(form) {
                const url = new URL(form.action || location.href, location.origin);
                const formData = new FormData(form);
                const request = new Request(url.href, {
                  method: form.method?.toUpperCase() || 'POST',
                  body: formData
                });

                try {
                  const response = await worker.default.fetch(request);

                  if (response.status >= 300 && response.status < 400) {
                    const location = response.headers.get('Location');
                    if (location) {
                      history.pushState({}, '', location);
                      await navigate(location);
                      return;
                    }
                  }

                  const html = await response.text();
                  const parser = new DOMParser();
                  const doc = parser.parseFromString(html, 'text/html');

                  const title = doc.querySelector('title');
                  if (title) document.title = title.textContent;

                  document.body.innerHTML = doc.body.innerHTML;
                  attachLinkHandlers();
                } catch (e) {
                  console.error('Form submission error:', e);
                }
              }

              function attachLinkHandlers() {
                document.querySelectorAll('a[href^="/"]').forEach(link => {
                  link.addEventListener('click', (e) => {
                    e.preventDefault();
                    const path = link.getAttribute('href');
                    history.pushState({}, '', path);
                    navigate(path);
                  });
                });

                document.querySelectorAll('form').forEach(form => {
                  form.addEventListener('submit', (e) => {
                    e.preventDefault();
                    submitForm(form);
                  });
                });
              }

              window.addEventListener('popstate', () => {
                navigate(location.pathname);
              });

              init();
            </script>
          </body>
          </html>
        HTML
        File.write(File.join(DIST_DIR, 'public', 'index.html'), index_html)
      end

      def generate_bundler
        log "  Generating bundler..."

        bundler = <<~JS
          // Bundle the Astro server entry for browser execution
          import * as esbuild from 'esbuild';
          import { join, dirname } from 'path';
          import { fileURLToPath } from 'url';

          const __dirname = dirname(fileURLToPath(import.meta.url));

          async function bundle() {
            console.log('Bundling worker for browser...');

            try {
              const result = await esbuild.build({
                entryPoints: [join(__dirname, 'dist/server/entry.mjs')],
                bundle: true,
                outfile: join(__dirname, 'dist/client/browser-worker.mjs'),
                format: 'esm',
                platform: 'browser',
                target: 'es2020',
                minify: false,
                sourcemap: true,
                define: {
                  'process.env.NODE_ENV': '"production"'
                },
                logLevel: 'info'
              });

              console.log('Bundle created: dist/client/browser-worker.mjs');
              return result;
            } catch (error) {
              console.error('Bundle failed:', error);
              process.exit(1);
            }
          }

          bundle();
        JS
        File.write(File.join(DIST_DIR, 'bundle-for-browser.mjs'), bundler)
      end

      def copy_assets
        # Copy public assets if they exist
        if File.directory?('public')
          Dir.glob('public/*').each do |asset|
            next if File.basename(asset) == 'index.html' # Don't overwrite generated index.html
            dest = File.join(DIST_DIR, 'public', File.basename(asset))
            if File.directory?(asset)
              FileUtils.cp_r(asset, dest)
            else
              FileUtils.cp(asset, dest)
            end
          end
        end
      end

      def install_dependencies
        log "  Installing dependencies..."

        Dir.chdir(DIST_DIR) do
          # Install from npm
          system('npm install 2>/dev/null') || warn("npm install failed")

          # Install ruby2js-rails from local if available
          ruby2js_rails = File.expand_path('../../../packages/ruby2js-rails', __dir__)
          if File.directory?(ruby2js_rails)
            system("npm install #{ruby2js_rails} 2>/dev/null")
          else
            system('npm install ruby2js-rails 2>/dev/null')
          end
        end
      end

      def run_build
        log "  Building..."

        Dir.chdir(DIST_DIR) do
          success = system('npm run build 2>&1')
          unless success
            warn "Build failed. Check #{DIST_DIR} for errors."
          end
        end
      end

      def extract_action(controller_code, action_name)
        return nil unless controller_code

        pattern = /def\s+#{Regexp.escape(action_name)}\b/
        match = controller_code.match(pattern)
        return nil unless match

        start_pos = match.end(0)
        depth = 1
        pos = start_pos

        while pos < controller_code.length && depth > 0
          case controller_code[pos..-1]
          when /\A\s*\b(def|class|module|do|if|unless|case|begin)\b/
            depth += 1
            pos += $&.length
          when /\A\s*\bend\b/
            depth -= 1
            pos += $&.length
          else
            pos += 1
          end
        end

        controller_code[start_pos...(pos - 3)].strip
      end
    end
  end
end
