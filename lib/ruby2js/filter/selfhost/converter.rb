# frozen_string_literal: true

# Selfhost Converter Filter - Transformations for Converter transpilation
#
# Handles patterns specific to the converter codebase:
# - handle :type do...end → on_type() method definitions
#
# The handle pattern: handle :nil do put 'null' end
# Becomes: on_nil() { this.put('null') }

require 'ruby2js'

module Ruby2JS
  module Filter
    module Selfhost
      module Converter
        include SEXP

        # Skip blocks guarded by `unless defined?(RUBY2JS_SELFHOST)`
        # This removes parser-gem specific code from the selfhosted output
        def on_if(node)
          condition, then_branch, else_branch = node.children

          # Check for: unless defined?(RUBY2JS_SELFHOST) ... end
          # In AST, `unless` is an `if` with nil then_branch and code in else_branch
          if then_branch.nil? && condition.type == :defined? &&
             condition.children[0]&.type == :const &&
             condition.children[0].children[1] == :RUBY2JS_SELFHOST
            # Skip this entire block
            return s(:hide)
          end

          super
        end

        # Transform method("on_#{name}") to use cleaned name without ? or !
        # This handles the handler registration loop in Converter#initialize
        def on_send(node)
          target, method_name, *args = node.children

          # Check for: method("on_#{name}")
          if target.nil? && method_name == :method && args.length == 1
            arg = args[0]
            if arg.type == :dstr && arg.children.length == 2
              prefix = arg.children[0]
              interpolation = arg.children[1]

              # Match pattern: "on_" + #{name}
              # Note: interpolation can be:
              # - :send (method call e.g., `name` from standalone)
              # - :lvar (block variable e.g., `name` from block)
              # - :begin wrapping one of the above (Parser gem style)
              var_node = interpolation
              if interpolation.type == :begin && interpolation.children.length == 1
                var_node = interpolation.children[0]
              end

              if prefix.type == :str && prefix.children[0] == 'on_' &&
                 [:send, :lvar].include?(var_node.type)

                # Transform to: this[`on_${name.replace(/[?!]$/, '')}`].bind(this)
                # Build: "on_" + name.to_s.sub(/[?!]$/, '')
                cleaned_name = s(:send,
                  s(:send, var_node, :to_s),
                  :sub,
                  s(:regexp, s(:str, '[?!]$'), s(:regopt)),
                  s(:str, '')
                )

                key_expr = s(:dstr,
                  s(:str, 'on_'),
                  s(:begin, cleaned_name)
                )

                # Build: this[key].bind(this)
                # Using :self for 'this', :[] for bracket access
                return process s(:send,
                  s(:send, s(:self), :[], key_expr),
                  :bind,
                  s(:self)
                )
              end
            end
          end

          super
        end

        # Transform ast_node? method to use typeof guard
        # Ruby's respond_to? becomes 'prop in obj' which throws on primitives
        # We transform to: typeof obj === 'object' && obj !== null && 'prop' in obj
        def on_def(node)
          method_name, args, body = node.children

          # Transform ast_node? method
          if method_name == :ast_node? && body
            # Replace respond_to? calls with guarded 'in' checks
            new_body = transform_respond_to_guards(body)
            return super(node.updated(nil, [method_name, args, new_body])) if new_body != body
          end

          super
        end

        # Transform respond_to? calls to use typeof guard for safe 'in' operator
        def transform_respond_to_guards(node)
          return node unless node.respond_to?(:type)

          if node.type == :send && node.children[1] == :respond_to? && node.children[2]
            target = node.children[0]
            prop = node.children[2]

            # Create: typeof(target) === 'object' && target !== null && prop in target
            type_check = s(:send,
              s(:send, nil, :typeof, target),
              :===,
              s(:str, 'object')
            )
            null_check = s(:send, target, :!=, s(:nil))
            in_check = s(:in?, prop, target)

            return s(:and, s(:and, type_check, null_check), in_check)
          end

          # Recursively process children
          if node.respond_to?(:children) && node.children.any?
            new_children = node.children.map do |child|
              if child.respond_to?(:type)
                transform_respond_to_guards(child)
              else
                child
              end
            end
            return node.updated(nil, new_children)
          end

          node
        end

        def on_block(node)
          call = node.children[0]
          args = node.children[1]
          body = node.children[2]

          # Check for handle :type do...end pattern
          if call.type == :send && call.children[0].nil? && call.children[1] == :handle
            types = call.children[2..-1]

            # All types should be symbols
            if types.all? { |t| t.type == :sym }
              # Create method definitions for each type, plus handler registration
              results = []

              types.each do |type_sym|
                type_name = type_sym.children[0].to_s
                method_name = "on_#{type_name}".to_sym

                # Create method definition
                results << s(:def, method_name, args, body)

                # Add handler registration with original type name
                # The constructor loop handles converting to JS-safe method names
                results << s(:send,
                  s(:attr, s(:const, nil, :Converter), :_handlers),
                  :push,
                  s(:str, type_name)
                )
              end

              return process(s(:begin, *results))
            end
          end

          super
        end
      end

      # NOTE: Converter is NOT added to DEFAULTS - it's loaded explicitly
      # when transpiling converter files
    end
  end
end
