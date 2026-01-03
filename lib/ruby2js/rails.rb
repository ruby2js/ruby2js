# Ruby2JS Rails integration
#
# Provides:
# - Stimulus middleware for serving Ruby controllers as JavaScript
# - Rake tasks for Ruby2JS operations

require 'rails'
require 'ruby2js'

class Ruby2JSRailtie < Rails::Railtie
  rake_tasks do
    Dir[File.expand_path('../tasks/*.rake', __dir__)].each do |file|
      load file
    end
  end

  # Transpile Ruby Stimulus controllers at boot time in development
  # so importmap discovers them. Production uses rake task via assets:precompile.
  initializer "ruby2js.transpile_controllers", before: :set_load_path do |app|
    next unless ::Rails.env.development?

    controllers_path = ::Rails.root.join("app/javascript/controllers")
    next unless controllers_path.exist?

    filters = [:stimulus, :functions, :esm]
    options = { autoexports: :default }

    Dir[controllers_path.join("*_controller.rb")].each do |rb_path|
      js_path = rb_path.sub(/\.rb$/, '.js')

      if !File.exist?(js_path) || File.mtime(rb_path) > File.mtime(js_path)
        begin
          js = Ruby2JS.convert(File.read(rb_path), filters: filters, **options)
          File.write(js_path, js.to_s)
          puts "Ruby2JS: Transpiled #{File.basename(rb_path)} -> #{File.basename(js_path)}"
        rescue => e
          warn "Ruby2JS: Failed to transpile #{rb_path}: #{e.message}"
        end
      end
    end
  end

  # Auto-register Stimulus middleware for development (hot reload)
  # Can be disabled with: config.ruby2js.stimulus_middleware = false
  initializer "ruby2js.stimulus_middleware" do |app|
    # Only use middleware in development for hot reload
    next unless ::Rails.env.development?

    # Default to enabled unless explicitly set to false
    enabled = if app.config.respond_to?(:ruby2js) && app.config.ruby2js.key?(:stimulus_middleware)
      app.config.ruby2js.stimulus_middleware
    else
      true
    end

    if enabled
      require_relative 'rails/stimulus_middleware'
      # Insert before ActionDispatch::Static so we transpile before assets are served
      app.middleware.insert_before ActionDispatch::Static, Ruby2JS::Rails::StimulusMiddleware
    end
  end

  # Configuration namespace
  config.ruby2js = ActiveSupport::OrderedOptions.new
end
