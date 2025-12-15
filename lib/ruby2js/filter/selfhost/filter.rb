# frozen_string_literal: true

# Selfhost Filter Filter - Transformations for Filter transpilation
#
# Handles patterns specific to transpiling Ruby2JS filters to JavaScript:
# - Skip external requires (ruby2js, regexp_parser, etc.)
# - Module wrapper: Ruby2JS::Filter::X → class X extends Filter.Processor
# - Generate import from ruby2js.js
# - Generate filter registration and export
# - super calls work naturally via class inheritance
# - Writer methods: def options=(x) → setter or regular method
# - AST comparisons: x == s(...) → nodesEqual(x, s(...))
# - Instance variable options: @options → _options
#
# This filter is NOT added to DEFAULTS - it's loaded explicitly
# when transpiling filter files.

require 'ruby2js'

module Ruby2JS
  module Filter
    module Selfhost
      module Filter
        include SEXP

        # External dependencies that should be skipped (not transpiled)
        SKIP_REQUIRES = %w[
          ruby2js
          regexp_parser
          pathname
          set
        ].freeze

        # Track if we're inside a filter module (Ruby2JS::Filter::X)
        def initialize(*args)
          super
          @selfhost_filter_name = nil
        end

        # Skip require/require_relative for external dependencies
        # Also handle AST structural comparisons (nodesEqual)
        def on_send(node)
          target, method_name, *args = node.children

          # Handle require 'external_dep'
          if target.nil? && method_name == :require && args.length == 1
            if args.first.type == :str
              path = args.first.children.first
              if SKIP_REQUIRES.any? { |dep| path == dep || path.start_with?("#{dep}/") }
                return s(:hide)
              end
            end
          end

          # Handle require_relative '../filter'
          if target.nil? && method_name == :require_relative && args.length == 1
            if args.first.type == :str
              path = args.first.children.first
              if path == '../filter' || path == './filter'
                return s(:hide)
              end
            end
          end

          # Handle == or === with s(...) on RHS
          if [:==, :===].include?(method_name) && args.length == 1 && target
            rhs = args[0]
            if rhs.type == :send && rhs.children[0].nil? && rhs.children[1] == :s
              # x == s(...) → nodesEqual(x, s(...))
              return process s(:send, nil, :nodesEqual, target, rhs)
            end
          end

          # Handle != with s(...) on RHS
          if method_name == :!= && args.length == 1 && target
            rhs = args[0]
            if rhs.type == :send && rhs.children[0].nil? && rhs.children[1] == :s
              # x != s(...) → !nodesEqual(x, s(...))
              return process s(:send, s(:send, nil, :nodesEqual, target, rhs), :'!')
            end
          end

          # Inside filters, convert process(...) to this.process(...)
          # Ruby resolves process to self.process via method lookup, but JS
          # would use the module-level process closure which isn't bound properly.
          # By using this.process(), we use the inherited method from Filter.Processor.
          if @selfhost_filter_name && target.nil? && method_name == :process
            return process node.updated(nil, [s(:self), method_name, *args])
          end

          # Also convert process_all(...) and process_children(...) to this.*
          if @selfhost_filter_name && target.nil? &&
             [:process_all, :process_children].include?(method_name)
            return process node.updated(nil, [s(:self), method_name, *args])
          end

          super
        end

        # Unwrap Ruby2JS::Filter::X module structure and generate wrapper
        # Input:
        #   module Ruby2JS
        #     module Filter
        #       module Functions
        #         ...
        #       end
        #       DEFAULTS << Functions
        #     end
        #   end
        # Output:
        #   import { ... } from 'filter_runtime.js'
        #   const Functions = (() => { ... })()
        #   registerFilter('Functions', Functions)
        #   export { Functions as default, Functions }
        def on_module(node)
          name_node = node.children[0]
          body = node.children[1..-1]

          # Check if this is `module Ruby2JS`
          if name_node&.type == :const &&
             name_node.children[0].nil? &&
             name_node.children[1] == :Ruby2JS

            # Look for inner `module Filter`
            inner = body.first
            inner = inner.children.first if inner&.type == :begin && inner.children.length == 1

            if inner&.type == :module
              filter_name_node = inner.children[0]
              if filter_name_node&.type == :const &&
                 filter_name_node.children[0].nil? &&
                 filter_name_node.children[1] == :Filter

                # Found module Ruby2JS::Filter - extract the inner filter module
                filter_body = inner.children[1..-1]
                filter_body = filter_body.first.children if filter_body.first&.type == :begin

                # Find the actual filter module (skip DEFAULTS << X)
                filter_modules = filter_body.select { |n| n&.type == :module }

                if filter_modules.length == 1
                  @selfhost_filter_name = filter_modules.first.children[0].children[1]
                  filter_name = @selfhost_filter_name.to_s

                  # Extract the filter module body
                  filter_mod = filter_modules.first
                  filter_mod_body = filter_mod.children[1..-1]
                  filter_mod_body = filter_mod_body.first.children if filter_mod_body.first&.type == :begin

                  # Convert module to class extending Filter.Processor
                  # This allows super to work properly in JavaScript
                  filter_class = s(:class,
                    s(:const, nil, filter_name.to_sym),
                    s(:const, s(:const, nil, :Filter), :Processor),
                    s(:begin, *filter_mod_body)
                  )

                  # Build the complete output with import, filter class, registration, export
                  return s(:begin,
                    # Import from ruby2js.js (filter runtime is bundled there)
                    # Path is relative to filters/ directory
                    s(:import,
                      '../ruby2js.js',
                      [s(:const, nil, :Parser),
                       s(:const, nil, :SEXP),
                       s(:const, nil, :s),
                       s(:const, nil, :S),
                       s(:const, nil, :ast_node),
                       s(:const, nil, :include),
                       s(:const, nil, :Filter),
                       s(:const, nil, :DEFAULTS),
                       s(:const, nil, :excluded),
                       s(:const, nil, :included),
                       s(:const, nil, :_options),
                       s(:const, nil, :filterContext),
                       s(:const, nil, :nodesEqual),
                       s(:const, nil, :registerFilter),
                       s(:const, nil, :Ruby2JS)]
                    ),
                    # The filter as a class extending Filter.Processor (enables proper super calls)
                    # Note: process(), process_all(), process_children() are now called via this.*
                    # so they use the inherited methods from Filter.Processor
                    process(filter_class),
                    # Register the filter (pass prototype for Object.assign compatibility)
                    s(:send, nil, :registerFilter, s(:str, filter_name), s(:attr, s(:const, nil, filter_name.to_sym), :prototype)),
                    # Export the filter
                    s(:export, :default, s(:const, nil, filter_name.to_sym)),
                    s(:export, s(:array, s(:const, nil, filter_name.to_sym)))
                  )
                end
              end
            end
          end

          super
        end

        # super calls now work naturally since filters are transpiled as classes
        # extending Filter.Processor. No transformation needed.

        # Note: def self.X in modules is now handled by the main converter
        # (lib/ruby2js/converter/module.rb) which transforms it to a regular
        # function that's included in the returned object.

        # Transform writer methods: def options=(x) → def set_options(x)
        # Note: This is a simple renaming; the preamble provides a proxy if needed
        def on_def(node)
          method_name = node.children[0]

          if method_name.to_s.end_with?('=')
            new_name = "set_#{method_name.to_s.chomp('=')}"
            node = node.updated(nil, [new_name.to_sym, *node.children[1..-1]])
          end

          super(node)
        end

        # Transform instance variables to module-level variables
        # @options → _options, @eslevel → _eslevel, etc.
        def on_ivar(node)
          var_name = node.children[0].to_s
          # @foo → _foo
          new_name = var_name.sub(/^@/, '_')
          s(:lvar, new_name.to_sym)
        end

        def on_ivasgn(node)
          var_name = node.children[0].to_s
          value = node.children[1]
          new_name = var_name.sub(/^@/, '_')
          s(:lvasgn, new_name.to_sym, process(value))
        end
      end

      # NOTE: Filter is NOT added to DEFAULTS - it's loaded explicitly
      # when transpiling filter files
    end
  end
end
