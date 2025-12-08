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

        def on_block(node)
          call = node.children[0]
          args = node.children[1]
          body = node.children[2]

          # Check for handle :type do...end pattern
          if call.type == :send && call.children[0].nil? && call.children[1] == :handle
            types = call.children[2..-1]

            # All types should be symbols
            if types.all? { |t| t.type == :sym }
              # Create method definitions for each type
              methods = types.map do |type_sym|
                type_name = type_sym.children[0].to_s
                method_name = "on_#{type_name}".to_sym
                s(:def, method_name, args, body)
              end

              # If single type, return single def; otherwise wrap in begin
              if methods.length == 1
                return process(methods.first)
              else
                return process(s(:begin, *methods))
              end
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
