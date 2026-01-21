# frozen_string_literal: true

require 'ruby2js'
require 'ruby2js/filter/erb'
require 'ruby2js/filter/rails/helpers'
require 'ruby2js/filter/functions'
require 'ruby2js/filter/esm'

module Ruby2JS
  module Spa
    # Transpiles ERB view templates to JavaScript render functions.
    #
    # Uses an ErbCompiler to convert ERB templates to Ruby buffer operations,
    # then applies Ruby2JS filters to generate JavaScript.
    #
    # Example:
    #   transpiler = ViewTranspiler.new('/path/to/rails/app')
    #   js_code = transpiler.transpile('articles', 'show')
    #
    class ViewTranspiler
      attr_reader :rails_root, :views_path

      # Filters used for ERB transpilation
      # Note: Rails::Helpers must come BEFORE Erb for method overrides to work
      DEFAULT_FILTERS = [
        Ruby2JS::Filter::Rails::Helpers,
        Ruby2JS::Filter::Erb,
        Ruby2JS::Filter::Functions,
        Ruby2JS::Filter::ESM
      ].freeze

      def initialize(rails_root, filters: nil, database: nil)
        @rails_root = rails_root.to_s
        @views_path = File.join(@rails_root, 'app', 'views')
        @filters = filters || DEFAULT_FILTERS
        @database = database || 'dexie'  # Default to browser database
      end

      # Transpile a single view template to JavaScript
      # @param controller [String, Symbol] Controller name (e.g., 'articles')
      # @param action [String, Symbol] Action name (e.g., 'show')
      # @return [String, nil] JavaScript code or nil if file not found
      def transpile(controller, action)
        file_path = view_file_path(controller, action)
        return nil unless File.exist?(file_path)

        template = File.read(file_path)
        transpile_erb(template)
      end

      # Transpile multiple views and return a hash of { 'controller/action' => js_code }
      def transpile_all(view_list)
        result = {}

        view_list.each do |view_spec|
          controller, action = parse_view_spec(view_spec)
          js = transpile(controller, action)
          result["#{controller}/#{action}"] = js if js
        end

        result
      end

      # Transpile and write all views to output directory
      # @param view_list [Array] List of view specs (e.g., ['articles/index', 'articles/show'])
      # @param output_dir [String] Directory to write output files
      def transpile_to_files(view_list, output_dir)
        FileUtils.mkdir_p(output_dir)

        view_list.each do |view_spec|
          controller, action = parse_view_spec(view_spec)
          js = transpile(controller, action)
          next unless js

          controller_dir = File.join(output_dir, controller.to_s)
          FileUtils.mkdir_p(controller_dir)

          file_path = File.join(controller_dir, "#{action}.js")
          File.write(file_path, js)
        end
      end

      # Transpile all views for a given controller
      def transpile_controller_views(controller)
        controller_dir = File.join(@views_path, controller.to_s)
        return {} unless Dir.exist?(controller_dir)

        result = {}
        Dir.glob(File.join(controller_dir, '*.html.erb')).each do |erb_path|
          action = File.basename(erb_path, '.html.erb')
          template = File.read(erb_path)
          js = transpile_erb(template)
          result["#{controller}/#{action}"] = js if js
        end

        result
      end

      # Generate a combined views module for a controller
      # @param controller [String] Controller name
      # @param views [Hash] Hash of { action => js_code }
      # @return [String] Combined JavaScript module
      def generate_views_module(controller, views)
        class_name = controller.to_s.split('_').map(&:capitalize).join
        imports = []
        exports = []

        views.keys.sort.each do |action|
          # Import from controller subdirectory
          imports << "import { render as #{action}_render } from './#{controller}/#{action}.js';"
          exports << "  #{action}: #{action}_render"
        end

        # Handle reserved word 'new'
        if views.key?('new')
          exports << "  $new: new_render"
        end

        <<~JS
          // #{class_name} views - auto-generated from .html.erb templates
          #{imports.join("\n")}

          export const #{class_name}Views = {
          #{exports.join(",\n")}
          };
        JS
      end

      private

      def view_file_path(controller, action)
        File.join(@views_path, controller.to_s, "#{action}.html.erb")
      end

      def parse_view_spec(spec)
        parts = spec.to_s.split('/')
        if parts.length >= 2
          [parts[-2], parts[-1]]
        else
          ['application', parts[0]]
        end
      end

      def transpile_erb(template)
        # Convert ERB to Ruby buffer operations
        ruby_src = erb_compile(template)

        # Transpile Ruby to JavaScript
        options = {
          eslevel: 2022,
          filters: @filters,
          database: @database
        }

        js = Ruby2JS.convert(ruby_src, options).to_s

        # Ensure export is present
        # Note: Function may not be at start if imports were added by rails/helpers filter
        # Handle both sync and async render functions
        unless js.include?('export ')
          js = js.sub(/(^|\n)(async )?function render/, '\1export \2function render')
        end

        js
      end

      # Compile ERB template to Ruby buffer operations
      # This matches the format expected by the Erb filter
      def erb_compile(template)
        ruby_code = "_buf = ::String.new;"
        pos = 0

        while pos < template.length
          erb_start = template.index("<%", pos)

          if erb_start.nil?
            # No more ERB tags, add remaining text
            text = template[pos..-1]
            ruby_code += " _buf << #{emit_ruby_string(text)};" if text && !text.empty?
            break
          end

          # Find end of ERB tag
          erb_end = template.index("%>", erb_start)
          raise "Unclosed ERB tag at position #{erb_start}" unless erb_end

          tag = template[(erb_start + 2)...erb_end]
          is_code_block = !tag.strip.start_with?("=") && !tag.strip.start_with?("-")

          # Add text before ERB tag
          if erb_start > pos
            text = template[pos...erb_start]
            # Strip trailing whitespace before code blocks
            if is_code_block && text.include?("\n")
              last_newline = text.rindex("\n")
              after_newline = text[(last_newline + 1)..-1] || ""
              text = text[0..last_newline] if after_newline =~ /^\s*$/
            end
            ruby_code += " _buf << #{emit_ruby_string(text)};" if text && !text.empty?
          end

          # Handle -%> (trim trailing newline)
          trim_trailing = tag.end_with?("-")
          tag = tag[0...-1] if trim_trailing
          tag = tag.strip

          is_output_expr = false
          if tag.start_with?("=")
            expr = tag[1..-1].strip
            if expr.end_with?(" do") || expr.end_with?("\tdo")
              ruby_code += " _buf.append= #{expr}\n"
            else
              ruby_code += " _buf << ( #{expr} ).to_s;"
              is_output_expr = true
            end
          elsif tag.start_with?("-")
            expr = tag[1..-1].strip
            ruby_code += " _buf << ( #{expr} ).to_s;"
            is_output_expr = true
          else
            ruby_code += " #{tag}\n"
          end

          pos = erb_end + 2

          # Trim trailing newline after code blocks
          if (trim_trailing || is_code_block) && pos < template.length && template[pos] == "\n"
            pos += 1
          end

          # For output expressions, add newline as separate literal
          if is_output_expr && pos < template.length && template[pos] == "\n"
            ruby_code += " _buf << #{emit_ruby_string("\n")};"
            pos += 1
          end
        end

        ruby_code += "\n_buf.to_s"
        ruby_code
      end

      def emit_ruby_string(str)
        escaped = str.gsub("\\", "\\\\").gsub('"', '\\"').gsub("\n", "\\n")
        "\"#{escaped}\""
      end
    end
  end
end
