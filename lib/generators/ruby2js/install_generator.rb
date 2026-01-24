# frozen_string_literal: true

require 'rails/generators'
require 'json'
require 'ruby2js/installer'

# Use Ruby2js (lowercase 'js') so Rails finds this as 'ruby2js:install'
# rather than 'ruby2_j_s:install'
module Ruby2js
  class InstallGenerator < Rails::Generators::Base
    desc "Set up Ruby2JS/Juntos for transpiling Rails to JavaScript"

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

      database = Ruby2JS::Installer.detect_database(destination_root)
      config_content = Ruby2JS::Installer.generate_vite_config(database: database)

      create_file config_path, config_content
    end

    def install_dependencies
      say_status :run, "npm install"
      # Use verbose: true so npm errors are visible
      run "npm install", verbose: true

      # Verify critical package was installed
      vite_path = 'node_modules/vite'
      unless File.directory?(vite_path)
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

      create_file binstub_path, Ruby2JS::Installer.generate_binstub
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

    def show_instructions
      say ""
      say "Ruby2JS/Juntos installed!", :green
      say ""
      say "Next steps:"
      say "  bin/juntos dev                - Start Vite dev server"
      say "  bin/juntos build              - Build with Vite"
      say "  bin/juntos server             - Production server (Node.js)"
      say ""
    end

    private

    def write_package_json(package_path)
      say_status :create, package_path

      app_name = Ruby2JS::Installer.detect_app_name(destination_root)
      package = Ruby2JS::Installer.generate_package_json(
        app_name: app_name,
        app_root: destination_root
      )

      create_file package_path, JSON.pretty_generate(package) + "\n"
    end

    def merge_package_json(package_path)
      say_status :update, package_path

      existing = JSON.parse(File.read(package_path))
      app_name = Ruby2JS::Installer.detect_app_name(destination_root)
      required = Ruby2JS::Installer.generate_package_json(
        app_name: existing["name"] || app_name,
        app_root: destination_root
      )

      added = Ruby2JS::Installer.merge_package_dependencies(existing, required)

      added.each do |type, name|
        say_status :add, "#{type}: #{name}"
      end

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
      # Group by base name, then pick the best extension
      by_basename = controller_files.group_by { |f| File.basename(f).sub(/\.(js|rb)$/, '') }
      unique_files = by_basename.map do |_basename, files|
        # Prefer .rb over .js
        files.find { |f| f.end_with?('.rb') } || files.first
      end

      unique_files.sort.each do |file|
        # Extract controller name from filename
        # hello_controller.js -> HelloController, "hello"
        # live_scores_controller.rb -> LiveScoresController, "live-scores"
        basename = File.basename(file).sub(/\.(js|rb)$/, '')
        name_part = basename.sub(/_controller$/, '')

        # Convert to class name (hello_world -> HelloWorld)
        class_name = name_part.split('_').map(&:capitalize).join('') + 'Controller'

        # Convert to Stimulus identifier (hello_world -> hello-world)
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
