# frozen_string_literal: true

# Selfhost Spec Filter - Transformations for test spec transpilation
#
# Handles:
# - _(...) wrapper removal (minitest expectation syntax)
# - @var → globalThis._var (spec instance variables use globalThis since
#   arrow functions don't have their own `this` binding)
#
# Note: Instance variables inside class definitions are NOT transformed
# (they use normal this._var via the converter).

require 'ruby2js'

module Ruby2JS
  module Filter
    module Selfhost
      module Spec
        include SEXP

        def initialize(*args)
          super
          @spec_class_depth = 0
        end

        def on_class(node)
          @spec_class_depth += 1
          result = super
          @spec_class_depth -= 1
          result
        end

        def on_send(node)
          target, method, *args = node.children

          # _(...) wrapper → just the inner expression
          # Minitest uses _() to wrap values for expectation syntax
          if target.nil? && method == :_ && args.length == 1
            return process(args.first)
          end

          super
        end

        # @var → globalThis._var (only outside class definitions)
        # Spec blocks use arrow functions which don't have `this` binding,
        # so we use globalThis as the shared context for instance variables.
        def on_ivar(node)
          # Inside a class, use default behavior (this._var)
          return super if @spec_class_depth > 0

          # Outside class: globalThis._var (property access, not method call)
          var_name = node.children.first.to_s.sub('@', '_')
          s(:attr, s(:gvar, :globalThis), var_name.to_sym)
        end

        # @var = value → globalThis._var = value (only outside class definitions)
        def on_ivasgn(node)
          # Inside a class, use default behavior
          return super if @spec_class_depth > 0

          var, value = node.children
          var_name = var.to_s.sub('@', '_')
          # globalThis._var = value (casgn-style for property assignment)
          s(:casgn, s(:gvar, :globalThis), var_name.to_sym, process(value))
        end
      end

      # NOTE: Spec is NOT added to DEFAULTS - it's loaded explicitly
      # when transpiling spec files
    end
  end
end
