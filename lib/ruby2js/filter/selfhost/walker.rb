# frozen_string_literal: true

# Selfhost Walker Filter - Transformations specific to PrismWalker transpilation
#
# Most transformations have been moved to general-purpose filters:
# - Functions filter: .freeze, .to_sym, .reject, negative index, 2-arg slice, .empty?
# - Pragma filter: # Pragma: skip for require/def/alias
#
# What remains here:
# - autoreturn for methods ending with constructor calls (Node.new(...))
#   This ensures visitor methods return their constructed Node values

require 'ruby2js'

module Ruby2JS
  module Filter
    module Selfhost
      module Walker
        include SEXP

        # Wrap method bodies in autoreturn when the last expression is a constructor call
        # This ensures methods like visit_integer_node return their Node.new(...) value
        def on_def(node)
          body = node.children[2]
          if body && needs_autoreturn?(body)
            node = node.updated(nil, [node.children[0], node.children[1], s(:autoreturn, body)])
          end

          super(node)
        end

        private

        # Check if an expression is a constructor call that should be returned
        def needs_autoreturn?(node)
          return false unless node

          # Handle begin blocks - check last expression
          if node.type == :begin
            return needs_autoreturn?(node.children.last)
          end

          # Check for Foo.new(...) pattern
          if node.type == :send
            target, method = node.children[0], node.children[1]
            return true if method == :new && target&.type == :const
          end

          false
        end
      end

      # Register Walker module
      DEFAULTS.push Walker
    end
  end
end
