# frozen_string_literal: true

require 'ruby2js'
require 'ruby2js/filter/rails/controller'
require 'ruby2js/filter/functions'
require 'ruby2js/filter/esm'

module Ruby2JS
  module Spa
    # Transpiles Rails controller files to JavaScript.
    #
    # Uses the Rails::Controller filter to transform controller classes
    # into JavaScript modules with async action methods.
    #
    # Example:
    #   transpiler = ControllerTranspiler.new('/path/to/rails/app')
    #   js_code = transpiler.transpile(:articles)
    #
    class ControllerTranspiler
      attr_reader :rails_root, :controllers_path

      # Filters used for controller transpilation
      DEFAULT_FILTERS = [
        Ruby2JS::Filter::Rails::Controller,
        Ruby2JS::Filter::Functions,
        Ruby2JS::Filter::ESM
      ].freeze

      def initialize(rails_root, filters: nil)
        @rails_root = rails_root.to_s
        @controllers_path = File.join(@rails_root, 'app', 'controllers')
        @filters = filters || DEFAULT_FILTERS
      end

      # Transpile a single controller to JavaScript
      # @param controller_name [String, Symbol] Controller name (e.g., :articles or :scores)
      # @param actions [Array, nil] Optional list of actions to include (nil = all)
      # @return [String, nil] JavaScript code or nil if file not found
      def transpile(controller_name, actions: nil)
        file_path = controller_file_path(controller_name)
        return nil unless File.exist?(file_path)

        source = File.read(file_path)

        # If specific actions are requested, filter the source
        if actions && actions.any?
          source = filter_controller_actions(source, actions)
        end

        options = {
          eslevel: 2022,
          filters: @filters
        }

        Ruby2JS.convert(source, options).to_s
      end

      # Transpile multiple controllers and return a hash of { name => js_code }
      def transpile_all(controller_list)
        result = {}

        controller_list.each do |spec|
          if spec.is_a?(Hash)
            # { articles: [:index, :show] }
            spec.each do |name, actions|
              js = transpile(name, actions: actions)
              result[name] = js if js
            end
          else
            # :articles (all actions)
            js = transpile(spec)
            result[spec.to_sym] = js if js
          end
        end

        result
      end

      # Transpile and write controllers to output directory
      def transpile_to_files(controller_list, output_dir)
        FileUtils.mkdir_p(output_dir)

        controller_list.each do |spec|
          if spec.is_a?(Hash)
            spec.each do |name, actions|
              js = transpile(name, actions: actions)
              write_controller(name, js, output_dir) if js
            end
          else
            js = transpile(spec)
            write_controller(spec, js, output_dir) if js
          end
        end
      end

      private

      def controller_file_path(name)
        File.join(@controllers_path, "#{name}_controller.rb")
      end

      def write_controller(name, js, output_dir)
        file_path = File.join(output_dir, "#{name}_controller.js")
        File.write(file_path, js)
      end

      # Filter controller source to include only specified actions
      # This parses the source, walks the AST, and removes unwanted methods
      def filter_controller_actions(source, actions)
        actions = actions.map(&:to_sym)

        ast, comments = Ruby2JS.parse(source)
        return source unless ast

        # Walk the AST and filter the class body
        filtered_ast = filter_class_body(ast, actions)

        # For simplicity, we'll regenerate Ruby source from the filtered AST
        # Since this is complex, for now we'll use a simpler approach:
        # Parse the source line by line and filter methods
        filter_source_methods(source, actions)
      end

      # Simple source-level filtering of controller methods
      # Keeps before_action, private section, and specified action methods
      def filter_source_methods(source, actions)
        lines = source.lines
        result = []
        in_method = false
        method_name = nil
        method_indent = 0
        keep_method = false
        in_private = false

        lines.each do |line|
          # Detect method definition
          if line =~ /^(\s*)def\s+(\w+)/
            in_method = true
            method_indent = $1.length
            method_name = $2.to_sym
            keep_method = actions.include?(method_name) || in_private
            result << line if keep_method
            next
          end

          # Detect end of method (same indentation as def)
          if in_method && line =~ /^(\s*)end\s*$/ && $1.length == method_indent
            result << line if keep_method
            in_method = false
            method_name = nil
            keep_method = false
            next
          end

          # Inside a method - keep or skip based on whether we're keeping it
          if in_method
            result << line if keep_method
            next
          end

          # Detect private keyword
          if line =~ /^\s*private\s*$/
            in_private = true
            result << line
            next
          end

          # Detect before_action - analyze which actions it applies to
          if line =~ /before_action\s+:(\w+)/
            callback_method = $1.to_sym

            # Check if this before_action applies to any of our actions
            if line =~ /only:\s*\[([^\]]+)\]/
              only_actions = $1.scan(/:(\w+)/).flatten.map(&:to_sym)
              applies = (only_actions & actions).any?
            elsif line =~ /except:\s*\[([^\]]+)\]/
              except_actions = $1.scan(/:(\w+)/).flatten.map(&:to_sym)
              applies = (actions - except_actions).any?
            else
              # No filter - applies to all actions
              applies = true
            end

            if applies
              # Rewrite before_action to only include relevant actions
              relevant = actions
              if line =~ /only:/
                only_actions = $1.scan(/:(\w+)/).flatten.map(&:to_sym) rescue []
                relevant = only_actions & actions
              end

              if relevant.length < actions.length && relevant.any?
                # Rewrite with filtered only:
                actions_str = relevant.map { |a| ":#{a}" }.join(', ')
                result << line.sub(/,?\s*only:\s*\[[^\]]+\]/, ", only: [#{actions_str}]")
                  .sub(/,?\s*except:\s*\[[^\]]+\]/, ", only: [#{actions_str}]")
              else
                result << line
              end
            end
            next
          end

          # Keep other class-level code
          result << line
        end

        result.join
      end

      # Walk AST and filter class body (more robust but complex)
      def filter_class_body(node, actions)
        return node unless node.respond_to?(:type)

        case node.type
        when :class
          class_name, superclass, body = node.children
          filtered_body = filter_class_body(body, actions)
          node.updated(nil, [class_name, superclass, filtered_body])
        when :begin
          filtered_children = node.children.map do |child|
            filter_node(child, actions)
          end.compact
          node.updated(nil, filtered_children)
        else
          node
        end
      end

      def filter_node(node, actions)
        return node unless node.respond_to?(:type)

        case node.type
        when :def
          method_name = node.children[0]
          # Keep action methods that are in our list
          actions.include?(method_name) ? node : nil
        when :send
          # Keep before_action, private declarations, etc.
          method = node.children[1]
          case method
          when :before_action, :private
            node
          else
            node
          end
        else
          node
        end
      end
    end
  end
end
