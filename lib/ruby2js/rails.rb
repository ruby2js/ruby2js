# Ruby2JS Rails integration
#
# Provides:
# - Stimulus middleware for serving Ruby controllers as JavaScript
# - Rake tasks for Ruby2JS operations

require 'rails'

class Ruby2JSRailtie < Rails::Railtie
  rake_tasks do
    Dir[File.expand_path('../tasks/*.rake', __dir__)].each do |file|
      load file
    end
  end

  # Auto-register Stimulus middleware in development
  # Can be disabled with: config.ruby2js.stimulus_middleware = false
  initializer "ruby2js.stimulus_middleware" do |app|
    # Check if middleware is explicitly disabled
    enabled = app.config.respond_to?(:ruby2js) &&
              app.config.ruby2js.respond_to?(:stimulus_middleware) ?
              app.config.ruby2js.stimulus_middleware : true

    if enabled
      require_relative 'rails/stimulus_middleware'
      app.middleware.use Ruby2JS::Rails::StimulusMiddleware
    end
  end

  # Configuration namespace
  config.ruby2js = ActiveSupport::OrderedOptions.new
end
