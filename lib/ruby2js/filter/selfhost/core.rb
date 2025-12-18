# frozen_string_literal: true

# Selfhost Core Filter - Universal transformations for self-hosting
#
# Transformations:
# - super/zsuper → dynamic prototype lookup (fixes filter composition)
#
# Note: Most transformations previously here are now handled by:
# - Ruby2JS core: symbols → strings conversion
# - comparison: :identity option: == → ===
# - functions filter: .freeze, negative index assignment, 2-arg slice, .reject
#
# Target-specific transformations are in separate filters:
# - selfhost/walker.rb - private/protected/public removal
# - selfhost/converter.rb - handle :type do...end patterns
# - selfhost/spec.rb - _() wrapper removal, minitest → JS test framework

require 'ruby2js'

module Ruby2JS
  module Filter
    module Selfhost
      module Core
        include SEXP

        def initialize(*args)
          super
          @selfhost_method_stack = []
        end

        # Track method context for super transformation
        # Store both method name and args node for zsuper handling
        def on_def(node)
          method_name = node.children[0]
          method_args = node.children[1]
          @selfhost_method_stack.push([method_name, method_args])
          result = super
          @selfhost_method_stack.pop
          result
        end

        def on_defs(node)
          method_name = node.children[1]
          method_args = node.children[2]
          @selfhost_method_stack.push([method_name, method_args])
          result = super
          @selfhost_method_stack.pop
          result
        end

        # Transform super to dynamic prototype lookup
        # Ruby: super or super(args)
        # JS: this._parent.method.call(this, args)
        #
        # This is needed because JavaScript's `super` is lexically bound to the
        # class where the method was defined, not where it ends up after filter
        # composition via Object.defineProperties. Ruby's super is dynamic.
        def on_zsuper(node)
          method_info = @selfhost_method_stack.last
          return super unless method_info

          method_name, method_args = method_info

          # Get args from enclosing method for zsuper (super with implicit args)
          # Extract arg names from the args node
          args = extract_arg_references(method_args)

          dynamic_super_call(method_name, args)
        end

        def on_super(node)
          method_info = @selfhost_method_stack.last
          return super unless method_info

          method_name, _ = method_info
          args = process_all(node.children)
          dynamic_super_call(method_name, args)
        end

        private

        # Extract lvar references from an args node for zsuper
        def extract_arg_references(args_node)
          return [] unless args_node

          args_node.children.map do |arg|
            case arg.type
            when :arg, :optarg, :kwarg, :kwoptarg
              s(:lvar, arg.children[0])
            when :restarg
              s(:splat, s(:lvar, arg.children[0] || :args))
            when :kwrestarg
              s(:kwsplat, s(:lvar, arg.children[0] || :kwargs))
            when :blockarg
              nil # block args aren't passed to super normally
            else
              nil
            end
          end.compact
        end

        def dynamic_super_call(method_name, args)
          # Generate: this._parent.method.call(this, ...args)
          #
          # The _parent property is injected during filter composition in
          # Pipeline.apply_filters, pointing to the parent class's prototype.
          # This replaces JavaScript's lexically-bound `super` with dynamic lookup.

          s(:send,
            s(:attr, s(:attr, s(:self), :_parent), method_name),
            :call,
            s(:self),
            *args)
        end
      end

      # Register the Core module - it's always loaded with selfhost
      DEFAULTS.push Core
    end
  end
end
