# Support for Turbo (Hotwire) custom stream actions.
#
# Converts Ruby DSL for custom Turbo Stream actions:
#   Turbo.stream_action :log do
#     console.log targetElements
#   end
#
# To JavaScript:
#   Turbo.StreamActions.log = function() {
#     console.log(this.targetElements)
#   }
#
# Works with @hotwired/turbo.

require 'ruby2js'

module Ruby2JS
  module Filter
    module Turbo
      include SEXP
      extend SEXP

      TURBO_STREAM_PROPS = Set.new(%i[
        action
        target
        targets
        targetElements
        templateContent
        dataset
        getAttribute
        hasAttribute
        setAttribute
        removeAttribute
      ])

      def initialize(*args)
        super
        @turbo_stream_action = false
      end

      def on_block(node)
        call = node.children.first
        return super unless call.type == :send

        target, method, *args = call.children

        # Turbo.stream_action :name do ... end
        if target == s(:const, nil, :Turbo) && method == :stream_action &&
           args.length == 1 && args.first.type == :sym

          action_name = args.first.children.first
          block_args = node.children[1]
          block_body = node.children[2]

          # Add import if ESM is enabled
          if modules_enabled?
            prepend_list << s(:import,
              ['@hotwired/turbo'],
              s(:const, nil, :Turbo))
          end

          # Process the block body with this.* prefixing enabled
          begin
            @turbo_stream_action = true
            processed_body = block_body ? process(block_body) : nil
          ensure
            @turbo_stream_action = false
          end

          # Generate: Turbo.StreamActions.name = function() { ... }
          s(:send,
            s(:attr, s(:const, nil, :Turbo), :StreamActions),
            "#{action_name}=".to_sym,
            s(:block, s(:send, nil, :proc), block_args, processed_body))
        else
          super
        end
      end

      def on_send(node)
        return super unless @turbo_stream_action

        target, method, *args = node.children

        # Convert unqualified Turbo stream properties to this.*
        if target.nil? && TURBO_STREAM_PROPS.include?(method)
          s(:send, s(:self), method, *process_all(args))
        else
          super
        end
      end
    end

    DEFAULTS.push Turbo
  end
end
