# frozen_string_literal: true

require 'rails/generators'

module Ruby2JS
  module Spa
    module Generators
      class InstallGenerator < Rails::Generators::Base
        source_root File.expand_path('templates', __dir__)

        desc "Creates a Ruby2JS SPA configuration file and sets up the build infrastructure"

        class_option :name, type: :string, default: 'app',
          desc: "Name of the SPA (used for output directory)"

        class_option :mount_path, type: :string, default: '/offline',
          desc: "URL path where the SPA will be mounted"

        def create_manifest
          template 'ruby2js_spa.rb.tt', 'config/ruby2js_spa.rb'
        end

        def add_to_gitignore
          gitignore = Rails.root.join('.gitignore')
          if File.exist?(gitignore)
            content = File.read(gitignore)
            entry = "/public/spa/"
            unless content.include?(entry)
              append_to_file '.gitignore', "\n# Ruby2JS SPA generated files\n#{entry}\n"
            end
          end
        end

        def show_instructions
          say ""
          say "Ruby2JS SPA installed!", :green
          say ""
          say "Next steps:"
          say "  1. Edit config/ruby2js_spa.rb to configure your SPA"
          say "  2. Run: rails ruby2js:spa:build"
          say "  3. Visit: #{options[:mount_path]}/"
          say ""
          say "Useful commands:"
          say "  rails ruby2js:spa:build  - Build the SPA"
          say "  rails ruby2js:spa:clean  - Remove generated files"
          say "  rails ruby2js:spa:info   - Show configuration"
          say ""
        end
      end
    end
  end
end
