# Support for Turbo (Hotwire) features.
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
# Also provides turbo_frame_tag helper for Turbo Frames:
#   turbo_frame_tag "comments" do
#     render @article.comments
#   end
#
# To HTML:
#   <turbo-frame id="comments">...</turbo-frame>
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

        # turbo_frame_tag "id" do ... end
        if target.nil? && method == :turbo_frame_tag
          return process_turbo_frame_tag(args, node.children[2])
        end

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
        target, method, *args = node.children

        # turbo_frame_tag "id", src: "/path" (without block)
        if target.nil? && method == :turbo_frame_tag
          return process_turbo_frame_tag(args, nil)
        end

        return super unless @turbo_stream_action

        # Convert unqualified Turbo stream properties to this.*
        if target.nil? && TURBO_STREAM_PROPS.include?(method)
          s(:send, s(:self), method, *process_all(args))
        else
          super
        end
      end

      private

      # Process turbo_frame_tag helper
      # turbo_frame_tag "id" do ... end
      # turbo_frame_tag "id", src: "/path"
      # turbo_frame_tag "id", src: "/path", loading: :lazy, target: :_top
      def process_turbo_frame_tag(args, block_body)
        # First arg is the id (string or symbol)
        id_node = args[0]
        id_value = case id_node.type
          when :str then id_node.children[0]
          when :sym then id_node.children[0].to_s
          else return super  # Dynamic id, let it pass through
        end

        # Build attributes string
        attrs = ["id=\"#{id_value}\""]

        # Process options hash if present
        if args[1]&.type == :hash
          args[1].children.each do |pair|
            key_node, value_node = pair.children
            key = key_node.children[0].to_s

            # Handle different value types
            value = case value_node.type
              when :str then value_node.children[0]
              when :sym then value_node.children[0].to_s
              when :true then 'true'
              when :false then 'false'
              else nil  # Dynamic value needs template literal
            end

            if value
              # Convert Ruby-style underscores to kebab-case for HTML attributes
              html_key = key.gsub('_', '-')
              attrs << "#{html_key}=\"#{value}\""
            else
              # Dynamic value - return a template literal expression
              # This case is handled separately below
            end
          end
        end

        attrs_str = attrs.join(' ')

        if block_body
          # With block: <turbo-frame id="...">content</turbo-frame>
          processed_body = process(block_body)

          # Generate string concatenation for the turbo-frame with content
          s(:send,
            s(:send,
              s(:str, "<turbo-frame #{attrs_str}>"),
              :+,
              processed_body),
            :+,
            s(:str, "</turbo-frame>"))
        else
          # Without block: <turbo-frame id="..." />
          s(:str, "<turbo-frame #{attrs_str}></turbo-frame>")
        end
      end
    end

    DEFAULTS.push Turbo
  end
end
