# frozen_string_literal: true

# Selfhost Walker Filter - Transformations for PrismWalker transpilation
#
# Handles idioms specific to the walker codebase.
#
# Note: Many transformations previously here are now in functions filter:
# - arr[-1] = x → arr[arr.length - 1] = x
# - str[offset, length] → str.slice(offset, offset + length)
# - .freeze → Object.freeze()
# - .reject { } → .filter { ! }
#
# What remains here:
# - Skip external requires (prism, node)
# - .to_sym removal (symbols are strings in JS)
# - .empty? → .length == 0
# - arr << x → arr.push(x) (ensure works in all contexts)
# - .reject(&:method) symbol-to-proc pattern
# - Remove Ruby-specific method definitions (respond_to?, etc.)
# - autoreturn for constructor calls

require 'ruby2js'

module Ruby2JS
  module Filter
    module Selfhost
      module Walker
        include SEXP

        # Skip external requires that shouldn't be bundled
        SKIP_REQUIRES = %w[prism node].freeze

        # Ruby-specific methods that don't translate to JS
        SKIP_METHODS = %i[
          respond_to?   # use 'prop' in obj or obj.prop !== undefined
          is_a?         # use instanceof
          kind_of?      # alias for is_a?
          is_method?    # Parser gem specific, not needed for JS nodes
          eql?          # use ==
          hash          # Ruby hash code
          to_sexp       # debugging
          inspect       # debugging
        ].freeze

        def on_send(node)
          target, method, *args = node.children

          # Skip external requires: require 'prism', require_relative 'node'
          if target.nil? && [:require, :require_relative].include?(method)
            if args.length == 1 && args[0].type == :str
              required = args[0].children[0]
              if SKIP_REQUIRES.include?(required)
                return s(:hide)
              end
            end
          end

          # .to_sym → no-op (symbols are strings in JS)
          if method == :to_sym && args.empty? && target
            return process target
          end

          # .empty? → .length == 0 (use :attr for property access)
          if method == :empty? && args.empty? && target
            return process s(:send, s(:attr, target, :length), :==, s(:int, 0))
          end

          # arr << x → arr.push(x) - ensure this works even in ternary expressions
          # The functions filter handles this for statements, but ternaries may bypass it
          if method == :<< && args.length == 1 && target
            return process s(:send, target, :push, args[0])
          end

          # .reject(&:method) → .filter with negated block
          # Handle symbol-to-proc pattern: reject(&:empty?) → filter(x => x.length != 0)
          if method == :reject && args.length == 1 && args[0]&.type == :block_pass
            block_pass = args[0]
            if block_pass.children[0]&.type == :sym
              method_sym = block_pass.children[0].children[0]
              # Create: .filter { |item| !item.method }
              arg = s(:arg, :item)
              body = s(:send, s(:begin, s(:send, s(:lvar, :item), method_sym)), :!)
              new_block = s(:block, s(:send, target, :filter), s(:args, arg), body)
              return process new_block
            end
          end

          super
        end

        # Remove Ruby-specific method definitions that don't make sense in JS
        # Also wrap method bodies in autoreturn when the last expression is:
        # - Node.new(...) or new Node(...) or similar constructors
        # This ensures methods return their constructed values
        def on_def(node)
          method_name = node.children[0]
          if SKIP_METHODS.include?(method_name)
            return s(:hide)
          end

          # Check if method body ends with a constructor call that should be returned
          body = node.children[2]
          if body && needs_autoreturn?(body)
            # Wrap body in autoreturn so the final expression is returned
            node = node.updated(nil, [node.children[0], node.children[1], s(:autoreturn, body)])
          end

          super(node)
        end

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

        # Remove class methods that are Ruby-specific (like self.===)
        def on_defs(node)
          method_name = node.children[1]
          if method_name == :===
            return s(:hide)
          end
          super
        end

        # Remove alias statements for Ruby-specific methods
        def on_alias(node)
          new_name = node.children[0]
          if new_name&.type == :sym
            method_name = new_name.children[0]
            if SKIP_METHODS.include?(method_name) || method_name == :loc || method_name == :to_a
              return s(:hide)
            end
          end
          super
        end
      end

      # Register Walker module
      DEFAULTS.push Walker
    end
  end
end
