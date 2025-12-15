# frozen_string_literal: true

# Selfhost Filter Filter - Transformations for Filter transpilation
#
# Handles patterns specific to transpiling Ruby2JS filters to JavaScript:
# - Skip external requires (ruby2js, regexp_parser, etc.)
# - Module wrapper: Ruby2JS::Filter::X → X class/object
# - Generate import from filter_runtime.js
# - Generate filter registration and export
# - super calls → process_children(node) or process(arg)
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
          @selfhost_in_filter_method = false
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

                  # Build the complete output with import, filter, registration, export
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
                       s(:const, nil, :processNode),
                       s(:const, nil, :process_children),
                       s(:const, nil, :process_all),
                       s(:const, nil, :_options),
                       s(:const, nil, :filterContext),
                       s(:const, nil, :nodesEqual),
                       s(:const, nil, :registerFilter),
                       s(:const, nil, :Ruby2JS)]
                    ),
                    # Wrapper function for process (filters use process() but runtime uses processNode to avoid Node.js conflict)
                    # Must be a function wrapper, not direct alias, because processNode gets reassigned by _setup
                    s(:casgn, nil, :process, s(:block, s(:send, nil, :lambda), s(:args, s(:arg, :node)), s(:send, nil, :processNode, s(:lvar, :node)))),
                    # The filter module itself
                    process(filter_modules.first),
                    # Register the filter
                    s(:send, nil, :registerFilter, s(:str, filter_name), s(:const, nil, filter_name.to_sym)),
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

        # Transform super calls in filter methods
        # - super with no args → process_children(node)
        # - super(arg) → process(arg)
        def on_zsuper(node)
          # zsuper is Ruby's `super` with implicit args
          # In filter context, replace with process_children(node)
          if @selfhost_in_filter_method
            return s(:send, nil, :process_children, s(:lvar, :node))
          end
          super
        end

        def on_super(node)
          args = node.children
          if @selfhost_in_filter_method && args.length == 1
            # super(arg) → process(arg)
            return s(:send, nil, :process, args[0])
          elsif @selfhost_in_filter_method && args.empty?
            # super() → process_children(node)
            return s(:send, nil, :process_children, s(:lvar, :node))
          end
          super
        end

        # Note: def self.X in modules is now handled by the main converter
        # (lib/ruby2js/converter/module.rb) which transforms it to a regular
        # function that's included in the returned object.

        # Track when we're in a filter method (on_X)
        def on_def(node)
          method_name = node.children[0]

          # Transform writer methods: def options=(x) → def set_options(x)
          # Note: This is a simple renaming; the preamble provides a proxy if needed
          if method_name.to_s.end_with?('=')
            new_name = "set_#{method_name.to_s.chomp('=')}"
            node = node.updated(nil, [new_name.to_sym, *node.children[1..-1]])
          end

          # Track if we're in an on_* method (filter handler)
          was_in_filter_method = @selfhost_in_filter_method
          @selfhost_in_filter_method = method_name.to_s.start_with?('on_')

          result = super(node)

          @selfhost_in_filter_method = was_in_filter_method
          result
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
