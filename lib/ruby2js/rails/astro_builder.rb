# frozen_string_literal: true

require 'fileutils'
require_relative 'erb_to_astro'

module Ruby2JS
  module Rails
    # Builds an Astro project from a Rails application.
    #
    # Converts Rails ERB views and controllers to Astro pages and components.
    #
    # Usage:
    #   AstroBuilder.new(options).build
    #
    class AstroBuilder
      DIST_DIR = 'dist'

      def initialize(options = {})
        @options = options
        @verbose = options[:verbose]
      end

      def build
        log "Converting Rails app to Astro..."

        setup_output_directories
        convert_views
        convert_partials
        copy_assets

        log "Astro conversion complete."
        true
      rescue => e
        warn "Error: #{e.message}"
        warn e.backtrace.first(5).join("\n") if @verbose
        false
      end

      private

      def log(message)
        puts message if @verbose || !@options[:quiet]
      end

      def setup_output_directories
        # Create Astro project structure
        FileUtils.mkdir_p(File.join(DIST_DIR, 'src', 'pages'))
        FileUtils.mkdir_p(File.join(DIST_DIR, 'src', 'components'))
        FileUtils.mkdir_p(File.join(DIST_DIR, 'src', 'layouts'))
        FileUtils.mkdir_p(File.join(DIST_DIR, 'src', 'lib'))
      end

      def convert_views
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
        log "  Converting #{controller_name}/#{action_name}..."

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
        when 'show', 'edit'
          File.join(DIST_DIR, 'src', 'pages', controller_name, '[id]', "#{action_name == 'show' ? 'index' : action_name}.astro")
        when 'new'
          File.join(DIST_DIR, 'src', 'pages', controller_name, 'new.astro')
        else
          File.join(DIST_DIR, 'src', 'pages', controller_name, "#{action_name}.astro")
        end

        FileUtils.mkdir_p(File.dirname(output_path))
        File.write(output_path, astro_content)

        log "    -> #{output_path}" if @verbose
      end

      def convert_partials
        # Find all partial ERB files across all view directories
        partial_files = Dir.glob('app/views/**/_*.html.erb')

        partial_files.each do |partial_file|
          convert_partial(partial_file)
        end
      end

      def convert_partial(partial_file)
        partial_name = File.basename(partial_file, '.html.erb').sub(/^_/, '')
        log "  Converting partial #{partial_name}..."

        erb_content = File.read(partial_file)

        # Get the controller/model name from directory path
        # e.g., app/views/comments/_form.html.erb -> comments -> comment
        dir_name = File.basename(File.dirname(partial_file))
        model_name = dir_name.end_with?('s') ? dir_name[0..-2] : dir_name

        # Determine component name
        base_component = partial_name.split('_').map(&:capitalize).join
        component_name = partial_name.end_with?('form') ? base_component : "#{base_component}Card"

        # For partials, we create a simpler Astro component
        # that receives props and renders the content
        astro_content = convert_partial_to_component(erb_content, partial_name, model_name, component_name)

        output_path = File.join(DIST_DIR, 'src', 'components', "#{component_name}.astro")
        File.write(output_path, astro_content)

        log "    -> #{output_path}" if @verbose
      end

      def convert_partial_to_component(erb_content, partial_name, model_name, component_name)
        # Convert ERB to Astro template using ErbToAstro in partial mode
        converter = PartialConverter.new(erb_content, partial_name, model_name, @options)
        converter.convert
      end

      def copy_assets
        # Copy public assets if they exist
        if File.directory?('public')
          FileUtils.cp_r('public/.', File.join(DIST_DIR, 'public'))
        end

        # Copy stylesheets if they exist
        if File.directory?('app/assets/stylesheets')
          FileUtils.mkdir_p(File.join(DIST_DIR, 'src', 'styles'))
          Dir.glob('app/assets/stylesheets/*.css').each do |css_file|
            FileUtils.cp(css_file, File.join(DIST_DIR, 'src', 'styles'))
          end
        end
      end

      def extract_action(controller_code, action_name)
        # Extract action method body from controller
        # Pattern: def action_name ... end (handling nested blocks)
        pattern = /def\s+#{Regexp.escape(action_name)}\b/

        match = controller_code.match(pattern)
        return nil unless match

        start_pos = match.end(0)
        depth = 1
        pos = start_pos

        # Find matching end
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

        # Extract the action body (between def and end)
        controller_code[start_pos...(pos - 3)].strip
      end
    end
  end
end
