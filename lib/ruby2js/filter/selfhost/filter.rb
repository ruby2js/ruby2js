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

        # Methods that should always be property access (no parentheses) in JS.
        # When nodes are created with s(), they lack location info, so is_method?
        # returns true and parentheses get added. We convert these to :attr nodes
        # to force property access.
        #
        # TODO: Revisit this - it's specific to selfhost transpilation. A more general
        # solution might be to have s() preserve some location metadata or to have
        # is_method? check the source_map option to know when we're doing selfhost.
        ALWAYS_PROPERTIES = %i[length size count children].freeze

        # Track if we're inside a filter module (Ruby2JS::Filter::X)
        def initialize(*args)
          super
          @selfhost_filter_name = nil
        end

        # Skip require/require_relative for external dependencies
        # Also handle AST structural comparisons (nodesEqual)
        def on_send(node)
          target, method_name, *args = node.children

          # Skip Ruby2JS.module_default = :xxx
          # This is a Ruby-side setting that doesn't apply in JS context
          if target&.type == :const &&
             target.children[0].nil? &&
             target.children[1] == :Ruby2JS &&
             method_name == :module_default=
            return s(:hide)
          end

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

          # Redirect Regexp::Scanner.scan(...) to scanRegexpGroups(...)
          # The regexp_parser gem isn't available in JS, so we use our minimal scanner.
          if target&.type == :const && method_name == :scan
            const_parent = target.children[0]
            const_name = target.children[1]
            if const_parent&.type == :const &&
               const_parent.children[0].nil? &&
               const_parent.children[1] == :Regexp &&
               const_name == :Scanner
              # Regexp::Scanner.scan(x) → scanRegexpGroups(x)
              return process s(:send, nil, :scanRegexpGroups, *args)
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

          # Convert es2015..es2025 to this.es20XX - these are instance methods
          # on Processor that check @options[:eslevel]. Ruby resolves them via
          # method lookup but JS needs explicit this.
          if @selfhost_filter_name && target.nil? && args.empty? &&
             [:es2015, :es2016, :es2017, :es2018, :es2019,
              :es2020, :es2021, :es2022, :es2023, :es2024, :es2025].include?(method_name)
            return s(:attr, s(:self), method_name)
          end

          # Convert S(...) to this.S(...) - S creates nodes with location preserved
          # from @ast. Ruby resolves it via method lookup, but JS needs explicit this.
          if @selfhost_filter_name && target.nil? && method_name == :S
            return process node.updated(nil, [s(:self), method_name, *args])
          end

          # Convert Ruby2JS.ast_node?(x) to ast_node(x)
          # ast_node is imported from ruby2js.js, not a method on Ruby2JS module
          if target&.type == :const && target.children == [nil, :Ruby2JS] &&
             method_name == :ast_node?
            return process s(:send, nil, :ast_node, *args)
          end

          # Convert Ruby2JS.convert(...) to convert(...)
          # convert is imported from ruby2js.js
          if target&.type == :const && target.children == [nil, :Ruby2JS] &&
             method_name == :convert
            return process s(:send, nil, :convert, *args)
          end

          # Convert Ruby2JS.parse(...) to parse(...)
          # parse is imported from ruby2js.js
          if target&.type == :const && target.children == [nil, :Ruby2JS] &&
             method_name == :parse
            return process s(:send, nil, :parse, *args)
          end

          # Convert length/size/count to :attr nodes to ensure property access.
          # Without this, nodes created with s() (no location info) get is_method?=true
          # and output as method calls like body.length() instead of body.length.
          if target && args.empty? && ALWAYS_PROPERTIES.include?(method_name)
            return s(:attr, process(target), method_name)
          end

          super
        end

        # Handle csend (safe navigation) nodes for ALWAYS_PROPERTIES
        def on_csend(node)
          target, method_name, *args = node.children

          # Convert length/size/count to :csend_attr for property access
          # (csend_attr is like attr but produces ?. instead of .)
          if target && args.empty? && ALWAYS_PROPERTIES.include?(method_name)
            # Use :csend with no args - the converter will output target?.length
            # The key is that without args and with :csend, it becomes property access
            return node.updated(:csend, [process(target), method_name])
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

                # Check for nested namespace modules (e.g., Rails::Model)
                # If we have one module that contains only modules, it's a namespace
                namespace_name = nil
                if filter_modules.length == 1
                  potential_namespace = filter_modules.first
                  ns_body = potential_namespace.children[1..-1]
                  ns_body = ns_body.first.children if ns_body.first&.type == :begin
                  inner_modules = ns_body.select { |n| n&.type == :module }

                  # If namespace contains modules and no direct method definitions, descend into it
                  has_methods = ns_body.any? { |n| n&.type == :def || n&.type == :defs }
                  if inner_modules.length >= 1 && !has_methods
                    namespace_name = potential_namespace.children[0].children[1].to_s
                    filter_modules = inner_modules
                    filter_body = ns_body
                  end
                end

                if filter_modules.length == 1
                  @selfhost_filter_name = filter_modules.first.children[0].children[1]
                  filter_name = @selfhost_filter_name.to_s
                  full_filter_name = namespace_name ? "#{namespace_name}_#{filter_name}" : filter_name

                  # Extract the filter module body
                  filter_mod = filter_modules.first
                  filter_mod_body = filter_mod.children[1..-1]
                  filter_mod_body = filter_mod_body.first.children if filter_mod_body.first&.type == :begin

                  # Convert module to class extending Filter.Processor
                  # This allows super to work properly in JavaScript
                  filter_class = s(:class,
                    s(:const, nil, full_filter_name.to_sym),
                    s(:const, s(:const, nil, :Filter), :Processor),
                    s(:begin, *filter_mod_body)
                  )

                  # Build output statements
                  # Import path is relative to filter location:
                  # - filters/foo.js imports from ../ruby2js.js
                  # - filters/rails/foo.js imports from ../../ruby2js.js
                  import_path = namespace_name ? '../../ruby2js.js' : '../ruby2js.js'
                  output_statements = [
                    # Import from ruby2js.js (filter runtime is bundled there)
                    s(:import,
                      import_path,
                      [s(:const, nil, :Parser),
                       s(:const, nil, :SEXP),
                       s(:const, nil, :s),
                       s(:const, nil, :S),
                       s(:const, nil, :ast_node),
                       s(:const, nil, :convert),
                       s(:const, nil, :parse),
                       s(:const, nil, :include),
                       s(:const, nil, :Filter),
                       s(:const, nil, :DEFAULTS),
                       s(:const, nil, :excluded),
                       s(:const, nil, :included),
                       s(:const, nil, :_options),
                       s(:const, nil, :filterContext),
                       s(:const, nil, :nodesEqual),
                       s(:const, nil, :registerFilter),
                       s(:const, nil, :scanRegexpGroups),
                       s(:const, nil, :Ruby2JS)]
                    ),
                    # The filter as a class extending Filter.Processor (enables proper super calls)
                    # Note: process(), process_all(), process_children() are now called via this.*
                    # so they use the inherited methods from Filter.Processor
                    process(filter_class),
                    # Register the filter (pass prototype for Object.assign compatibility)
                    s(:send, nil, :registerFilter, s(:str, full_filter_name), s(:attr, s(:const, nil, full_filter_name.to_sym), :prototype))
                  ]

                  # For namespaced filters (e.g., Rails::Model), also register under Ruby2JS.Filter.Rails.Model
                  if namespace_name
                    # Ruby2JS.Filter.Rails = Ruby2JS.Filter.Rails || {}
                    output_statements << s(:op_asgn,
                      s(:attr, s(:attr, s(:const, nil, :Ruby2JS), :Filter), namespace_name.to_sym),
                      :'||',
                      s(:hash)
                    )
                    # Ruby2JS.Filter.Rails.Model = Rails_Model.prototype
                    output_statements << s(:send,
                      s(:attr, s(:attr, s(:const, nil, :Ruby2JS), :Filter), namespace_name.to_sym),
                      "#{filter_name}=".to_sym,
                      s(:attr, s(:const, nil, full_filter_name.to_sym), :prototype)
                    )
                  end

                  # Export the filter
                  output_statements << s(:export, :default, s(:const, nil, full_filter_name.to_sym))
                  output_statements << s(:export, s(:array, s(:const, nil, full_filter_name.to_sym)))

                  return s(:begin, *output_statements)
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
        # Transform initialize → _filter_init (called by runtime after instantiation)
        # Note: This is a simple renaming; the preamble provides a proxy if needed
        def on_def(node)
          method_name = node.children[0]

          if method_name == :initialize
            # Transform initialize to _filter_init
            # The runtime will call this after instantiation with _parent set correctly
            node = node.updated(nil, [:_filter_init, *node.children[1..-1]])
          elsif method_name.to_s.end_with?('=')
            new_name = "set_#{method_name.to_s.chomp('=')}"
            node = node.updated(nil, [new_name.to_sym, *node.children[1..-1]])
          end

          super(node)
        end

        # Transform instance variables to this._foo properties
        # This ensures they persist across method calls (unlike local let variables)
        def on_ivar(node)
          var_name = node.children[0].to_s
          new_name = var_name.sub(/^@/, '_')
          s(:attr, s(:self), new_name.to_sym)
        end

        def on_ivasgn(node)
          var_name = node.children[0].to_s
          value = node.children[1]
          new_name = var_name.sub(/^@/, '_')
          # Use send with setter method: this._foo = value → (send (self) :_foo= value)
          s(:send, s(:self), "#{new_name}=".to_sym, process(value))
        end

        # Handle @foo ||= value → this._foo ??= value
        def on_or_asgn(node)
          target, value = node.children
          if target.type == :ivasgn
            var_name = target.children[0].to_s
            new_name = var_name.sub(/^@/, '_')
            # Transform to (or_asgn (attr (self) :_foo) value) which becomes this._foo ??= value
            node.updated(nil, [s(:attr, s(:self), new_name.to_sym), process(value)])
          else
            super
          end
        end

        # Handle @foo &&= value → this._foo &&= value
        def on_and_asgn(node)
          target, value = node.children
          if target.type == :ivasgn
            var_name = target.children[0].to_s
            new_name = var_name.sub(/^@/, '_')
            node.updated(nil, [s(:attr, s(:self), new_name.to_sym), process(value)])
          else
            super
          end
        end

        # Handle @foo += value → this._foo += value
        def on_op_asgn(node)
          target, op, value = node.children
          if target.type == :ivasgn
            var_name = target.children[0].to_s
            new_name = var_name.sub(/^@/, '_')
            node.updated(nil, [s(:attr, s(:self), new_name.to_sym), op, process(value)])
          else
            super
          end
        end
      end

      # NOTE: Filter is NOT added to DEFAULTS - it's loaded explicitly
      # when transpiling filter files
    end
  end
end
