# frozen_string_literal: true

require 'rails/engine'

module Ruby2JS
  module Spa
    class Engine < ::Rails::Engine
      isolate_namespace Ruby2JS::Spa

      # Load rake tasks
      rake_tasks do
        load File.expand_path('../../tasks/ruby2js_spa.rake', __dir__)
      end

      # Auto-configure middleware if manifest exists
      initializer 'ruby2js.spa.middleware' do |app|
        manifest_path = Rails.root.join('config', 'ruby2js_spa.rb')

        if File.exist?(manifest_path)
          require_relative 'middleware'

          # Load the manifest to get mount_path
          load manifest_path
          manifest = Ruby2JS::Spa.configuration

          if manifest&.mount_path
            app.middleware.use Ruby2JS::Spa::Middleware,
              mount_path: manifest.mount_path,
              spa_root: Rails.root.join('public', 'spa', manifest.name.to_s)
          end
        end
      end
    end
  end
end
