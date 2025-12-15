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

        # Methods that are always method calls in Ruby, never property accesses
        # These need to be marked as :call type to ensure they get () in JS
        # is_method? is critical - Ruby's is_method? becomes is_method in JS, must be called with ()
        # reverse is needed because arr.reverse.each becomes for-of loop in JS
        # getOwnProps is a method on Namespace class that returns an object
        ALWAYS_METHODS = %i[pop shift is_method? reverse sort getOwnProps dup chomp].freeze

        # Properties that should always be accessed without () in JS
        # Even though Ruby calls them as methods, they're properties in JS
        ALWAYS_PROPERTIES = %i[length children type].freeze

        # Transform method("on_#{name}") to use cleaned name without ? or !
        # This handles the handler registration loop in Converter#initialize
        def on_send(node)
          target, method_name, *args = node.children

          # Protect `puts` calls from functions filter transformation
          # The functions filter transforms `puts(x)` to `console.log(x)` but
          # in Serializer, `puts` is a method that adds tokens to output lines
          if target.nil? && method_name == :puts
            # Transform to self.puts to prevent functions filter from changing it
            return process node.updated(nil, [s(:self), method_name, *args])
          end

          # Force .pop, .shift to always be method calls
          # In Ruby these are always methods; in JS they could be property access
          # Mark as :call type so converter adds parentheses
          # Don't re-process - just update the type and return (avoids infinite loop)
          if target && ALWAYS_METHODS.include?(method_name) && args.empty?
            return node.updated(:call, node.children)
          end

          # Force .length, .children, .type to always be property access
          # In Ruby these are methods; in JS they're properties (no parens)
          # Mark as :attr type so converter doesn't add parentheses
          # Only apply when there's a target and we've actually processed this node
          if target && ALWAYS_PROPERTIES.include?(method_name) && args.empty? && node.type == :send
            return process(node.updated(:attr, [target, method_name]))
          end

          # Transform Ruby2JS::Node.new(...) to new globalThis.Ruby2JS.Node(...)
          # The converter module defines its own Ruby2JS local, so we need
          # to reference the global Node class instead
          if target&.type == :const && method_name == :new
            parent_const = target.children[0]
            const_name = target.children[1]
            if const_name == :Node &&
               parent_const&.type == :const &&
               parent_const.children == [nil, :Ruby2JS]
              # Build: new globalThis.Ruby2JS.Node(args)
              # Use :lvar for globalThis (no parens), :attr for property access
              global_node = s(:attr,
                s(:attr,
                  s(:lvar, :globalThis),
                  :Ruby2JS
                ),
                :Node
              )
              return process node.updated(nil, [global_node, :new, *args])
            end
          end

          # Transform self.ivars.include?(var) to var in this.ivars
          # ivars is a Hash/Object, not an Array, so we need 'in' check
          if method_name == :include? && args.length == 1 &&
             target&.type == :send && target.children[1] == :ivars
            return process s(:in?, args[0], target)
          end

          # Transform respond_to?(:type) to safe in-check with typeof guard
          # Ruby's respond_to? becomes 'prop in obj' which throws on primitives/null
          # Transform to: typeof obj === 'object' && obj !== null && 'prop' in obj
          if method_name == :respond_to? && args.length >= 1
            actual_target = target || s(:self)
            prop = args[0]
            # Create: typeof(target) === 'object' && target !== null && prop in target
            type_check = s(:send,
              s(:send, nil, :typeof, actual_target),
              :===,
              s(:str, 'object')
            )
            null_check = s(:send, actual_target, :'!=', s(:nil))
            in_check = s(:in?, prop, actual_target)

            return process s(:and, s(:and, type_check, null_check), in_check)
          end

          # Transform array slice comparison: x.children[0..1] == [nil, :async]
          # In JS, array === array always fails (reference comparison)
          # Transform to element-wise: x.children[0] === null && x.children[1] === "async"
          if [:==, :===].include?(method_name) && args.length == 1
            # Check for: target[range] == [literal array]
            if target&.type == :send && target.children[1] == :[]
              range_arg = target.children[2]
              rhs = args[0]

              # Match: x[0..n] == [a, b, ...]  where range is an irange
              if range_arg&.type == :irange && rhs&.type == :array
                range_start = range_arg.children[0]
                base_expr = target.children[0]  # e.g., m.children

                # Build element-wise comparisons
                comparisons = rhs.children.each_with_index.map do |elem, idx|
                  # Calculate actual index: range_start + idx
                  if range_start&.type == :int
                    actual_idx = s(:int, range_start.children[0] + idx)
                  else
                    actual_idx = s(:int, idx)
                  end

                  # base_expr[actual_idx] === elem
                  s(:send, s(:send, base_expr, :[], actual_idx), :===, elem)
                end

                # Combine with &&
                result = comparisons.reduce { |acc, cmp| s(:and, acc, cmp) }
                return process result
              end
            end
          end

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

                # Transform to: this[`on_${name.replace(/!$/, '_bang').replace(/\?$/, '_q')}`].bind(this)
                # Build: "on_" + name.to_s.sub(/!$/, '_bang').sub(/\?$/, '_q')
                cleaned_name = s(:send,
                  s(:send,
                    s(:send, var_node, :to_s),
                    :sub,
                    s(:regexp, s(:str, '!$'), s(:regopt)),
                    s(:str, '_bang')
                  ),
                  :sub,
                  s(:regexp, s(:str, '\\?$'), s(:regopt)),
                  s(:str, '_q')
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
              # Ruby allows ! and ? in method names, JS doesn't. Convert:
              #   send! -> send_bang
              #   send? -> send_q
              results = []

              types.each do |type_sym|
                type_name = type_sym.children[0].to_s
                # Convert to JS-safe method name
                js_type_name = type_name.sub(/!$/, '_bang').sub(/\?$/, '_q')
                js_method_name = "on_#{js_type_name}".to_sym

                # Create method definition
                results << s(:def, js_method_name, args, body)

                # Register handler with original type name
                # The constructor loop will convert to JS-safe method names
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
