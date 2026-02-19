# frozen_string_literal: true

require 'rails/generators'
require 'json'

# Use Ruby2js (lowercase 'js') so Rails finds this as 'ruby2js:install'
# rather than 'ruby2_j_s:install'
module Ruby2js
  class InstallGenerator < Rails::Generators::Base
    desc "Set up Ruby2JS/Juntos for transpiling Rails to JavaScript"

    # Core dependencies - database adapters are installed on-demand
    RELEASES_URL = 'https://ruby2js.github.io/ruby2js/releases'.freeze
    CORE_DEPENDENCIES = {
      'juntos' => "#{RELEASES_URL}/juntos-beta.tgz",
      'juntos-dev' => "#{RELEASES_URL}/juntos-dev-beta.tgz"
    }.freeze
    DEV_DEPENDENCIES = {
      'vite' => '^6.0.0',
      'vitest' => '^2.0.0'
    }.freeze

    def create_package_json
      package_path = 'package.json'

      if File.exist?(package_path)
        merge_package_json(package_path)
      else
        write_package_json(package_path)
      end
    end

    def create_vite_config
      config_path = 'vite.config.js'

      if File.exist?(config_path)
        say_status :skip, "vite.config.js already exists"
        return
      end

      create_file config_path, <<~JS
        import { defineConfig } from 'vite';
        import { juntos } from 'juntos-dev/vite';

        export default defineConfig({
          plugins: juntos()
        });
      JS
    end

    def create_vitest_config
      config_path = 'vitest.config.js'

      if File.exist?(config_path)
        say_status :skip, "vitest.config.js already exists"
        return
      end

      create_file config_path, <<~JS
        import { defineConfig, mergeConfig } from 'vitest/config';
        import viteConfig from './vite.config.js';

        export default mergeConfig(viteConfig, defineConfig({
          test: {
            globals: true,
            environment: 'node',
            include: ['test/**/*.test.mjs', 'test/**/*.test.js'],
            setupFiles: ['./test/setup.mjs']
          }
        }));
      JS
    end

    def create_test_setup
      setup_path = 'test/setup.mjs'

      if File.exist?(setup_path)
        say_status :skip, "test/setup.mjs already exists"
        return
      end

      create_file setup_path, <<~JS
        // Test setup for Vitest
        // Initializes the database before each test

        import { beforeAll, beforeEach } from 'vitest';

        beforeAll(async () => {
          // Import models (registers them with Application and modelRegistry)
          await import('juntos:models');

          // Configure migrations
          const rails = await import('juntos:rails');
          const migrations = await import('juntos:migrations');
          rails.Application.configure({ migrations: migrations.migrations });
        });

        beforeEach(async () => {
          // Fresh in-memory database for each test
          const activeRecord = await import('juntos:active-record');
          await activeRecord.initDatabase({ database: ':memory:' });

          const rails = await import('juntos:rails');
          await rails.Application.runMigrations(activeRecord);
        });
      JS
    end

    def install_dependencies
      say_status :run, "npm install"
      run "npm install", verbose: true

      # Verify critical package was installed
      unless File.directory?('node_modules/vite')
        say_status :warn, "vite not found, installing explicitly"
        run "npm install vite@^6.0.0 --save-dev", verbose: true
      end
    end

    def create_binstub
      binstub_path = "bin/juntos"

      if File.exist?(binstub_path)
        say_status :skip, "bin/juntos already exists"
        return
      end

      create_file binstub_path, <<~SHELL
        #!/bin/sh
        # Juntos - Rails patterns, JavaScript runtimes
        # This binstub delegates to the juntos CLI from juntos-dev
        exec npx juntos "$@"
      SHELL
      chmod binstub_path, 0755
    end

    def update_stimulus_controllers
      controllers_dir = 'app/javascript/controllers'
      index_path = "#{controllers_dir}/index.js"

      # Clean up .js files created by Rails mode (ruby2js:transpile_controllers).
      # Juntos mode uses Vite which transpiles .rb files on-the-fly, so these
      # pre-transpiled .js files are redundant and would cause duplicate imports.
      cleanup_redundant_js_controllers(controllers_dir)

      return unless File.exist?(index_path)

      content = File.read(index_path)

      # Check if this is Rails' importmap-style controllers/index.js
      # (uses @hotwired/stimulus-loading for lazy loading)
      if content.include?('stimulus-loading')
        say_status :update, index_path

        # Find all controller files
        controller_files = Dir.glob("#{controllers_dir}/*_controller.{js,rb}").map do |f|
          File.basename(f)
        end.sort

        # Generate Vite-compatible controllers/index.js
        new_content = generate_vite_controllers_index(controller_files)

        remove_file index_path
        create_file index_path, new_content
      end
    end

    def show_instructions
      say ""
      say "Ruby2JS/Juntos installed!", :green
      say ""
      say "Next steps:"
      say "  bin/juntos dev                - Start Vite dev server"
      say "  bin/juntos build              - Build with Vite"
      say "  bin/juntos server             - Production server (Node.js)"
      say "  npm test                      - Run tests with Vitest"
      say ""
      say "Database adapters are installed automatically when needed."
      say ""
    end

    private

    # Remove .js files that have corresponding .rb files.
    # These are created by Rails mode for importmap but conflict with Juntos mode
    # where Vite transpiles .rb files on-the-fly.
    def cleanup_redundant_js_controllers(controllers_dir)
      return unless File.directory?(controllers_dir)

      Dir.glob("#{controllers_dir}/*_controller.rb").each do |rb_path|
        js_path = rb_path.sub(/\.rb$/, '.js')
        if File.exist?(js_path)
          say_status :remove, File.basename(js_path), :yellow
          remove_file js_path
        end
      end
    end

    def detect_app_name
      app_rb = File.join(destination_root, "config/application.rb")
      if File.exist?(app_rb)
        content = File.read(app_rb)
        if content =~ /module\s+(\w+)/
          return $1.gsub(/([a-z])([A-Z])/, '\1_\2').downcase
        end
      end
      File.basename(destination_root).gsub(/[^a-z0-9_-]/i, '_').downcase
    end

    def write_package_json(package_path)
      say_status :create, package_path

      package = {
        "name" => detect_app_name,
        "type" => "module",
        "scripts" => {
          "dev" => "vite",
          "build" => "vite build",
          "preview" => "vite preview",
          "test" => "vitest run"
        },
        "dependencies" => CORE_DEPENDENCIES.dup,
        "devDependencies" => DEV_DEPENDENCIES.dup
      }

      create_file package_path, JSON.pretty_generate(package) + "\n"
    end

    def merge_package_json(package_path)
      say_status :update, package_path

      existing = JSON.parse(File.read(package_path))
      existing["type"] ||= "module"
      existing["dependencies"] ||= {}
      existing["devDependencies"] ||= {}
      existing["scripts"] ||= {}

      added = []

      # Add core dependencies
      CORE_DEPENDENCIES.each do |name, version|
        unless existing["dependencies"].key?(name)
          existing["dependencies"][name] = version
          added << "dependency: #{name}"
        end
      end

      # Add dev dependencies
      DEV_DEPENDENCIES.each do |name, version|
        unless existing["devDependencies"].key?(name)
          existing["devDependencies"][name] = version
          added << "devDependency: #{name}"
        end
      end

      # Add scripts if missing
      { "dev" => "vite", "build" => "vite build", "preview" => "vite preview", "test" => "vitest run" }.each do |name, cmd|
        unless existing["scripts"].key?(name)
          existing["scripts"][name] = cmd
          added << "script: #{name}"
        end
      end

      added.each { |item| say_status :add, item }

      remove_file package_path
      create_file package_path, JSON.pretty_generate(existing) + "\n"
    end

    # Generate a Vite-compatible controllers/index.js that imports and registers
    # all Stimulus controllers. Rails 7+ generates an importmap-style version that
    # uses @hotwired/stimulus-loading, which doesn't work with Vite.
    def generate_vite_controllers_index(controller_files)
      imports = []
      registrations = []

      # Deduplicate: if both .js and .rb exist, prefer .rb (Ruby2JS)
      by_basename = controller_files.group_by { |f| File.basename(f).sub(/\.(js|rb)$/, '') }
      unique_files = by_basename.map do |_basename, files|
        files.find { |f| f.end_with?('.rb') } || files.first
      end

      unique_files.sort.each do |file|
        basename = File.basename(file).sub(/\.(js|rb)$/, '')
        name_part = basename.sub(/_controller$/, '')
        class_name = name_part.split('_').map(&:capitalize).join('') + 'Controller'
        identifier = name_part.tr('_', '-')

        imports << "import #{class_name} from \"./#{file}\";"
        registrations << "application.register(\"#{identifier}\", #{class_name});"
      end

      <<~JS
        import { Application } from "@hotwired/stimulus";

        #{imports.join("\n")}

        const application = Application.start();

        #{registrations.join("\n")}

        export { application };
      JS
    end
  end
end
