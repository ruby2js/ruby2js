# frozen_string_literal: true

namespace :ruby2js do
  namespace :spa do
    desc "Build offline SPA from config/ruby2js_spa.rb manifest"
    task build: :environment do
      require 'ruby2js/spa'

      manifest_path = Rails.root.join('config', 'ruby2js_spa.rb')

      unless File.exist?(manifest_path)
        abort "Manifest not found: #{manifest_path}\nRun: rails generate ruby2js:spa:install"
      end

      # Load the manifest
      load manifest_path
      manifest = Ruby2JS::Spa.configuration

      unless manifest
        abort "No Ruby2JS::Spa.configure block found in #{manifest_path}"
      end

      # Build the SPA
      builder = Ruby2JS::Spa::Builder.new(manifest, rails_root: Rails.root)
      builder.build
    end

    desc "Clean generated SPA files"
    task clean: :environment do
      require 'ruby2js/spa'

      manifest_path = Rails.root.join('config', 'ruby2js_spa.rb')

      if File.exist?(manifest_path)
        load manifest_path
        manifest = Ruby2JS::Spa.configuration

        if manifest&.name
          spa_dir = Rails.root.join('public', 'spa', manifest.name.to_s)
          if Dir.exist?(spa_dir)
            require 'fileutils'
            FileUtils.rm_rf(spa_dir)
            puts "Removed: #{spa_dir}"
          else
            puts "Nothing to clean: #{spa_dir} does not exist"
          end
        end
      else
        puts "No manifest found at #{manifest_path}"
      end
    end

    desc "Show SPA manifest configuration"
    task info: :environment do
      require 'ruby2js/spa'

      manifest_path = Rails.root.join('config', 'ruby2js_spa.rb')

      unless File.exist?(manifest_path)
        abort "Manifest not found: #{manifest_path}\nRun: rails generate ruby2js:spa:install"
      end

      load manifest_path
      manifest = Ruby2JS::Spa.configuration

      unless manifest
        abort "No Ruby2JS::Spa.configure block found in #{manifest_path}"
      end

      puts "Ruby2JS SPA Configuration"
      puts "=" * 40
      puts "Name:       #{manifest.name}"
      puts "Mount path: #{manifest.mount_path}"
      puts "Output:     public/spa/#{manifest.name}/"
      puts

      if manifest.model_config.included_models.any?
        puts "Models:     #{manifest.model_config.included_models.join(', ')}"
      end

      if manifest.controller_config.included_controllers.any?
        puts "Controllers:"
        manifest.controller_config.included_controllers.each do |name, config|
          if config[:only]
            puts "  - #{name} (only: #{config[:only].join(', ')})"
          else
            puts "  - #{name}"
          end
        end
      end

      if manifest.view_config.included_views.any?
        puts "Views:"
        manifest.view_config.included_views.each { |v| puts "  - #{v}" }
      end

      if manifest.stimulus_config.included_controllers.any?
        puts "Stimulus:"
        manifest.stimulus_config.included_controllers.each { |c| puts "  - #{c}" }
      end
    end
  end
end
