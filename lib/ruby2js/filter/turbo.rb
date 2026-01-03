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
# And turbo_stream_from for subscribing to broadcast channels:
#   turbo_stream_from "article_#{@article.id}_comments"
#
# To JavaScript:
#   TurboBroadcast.subscribe(`article_${this.article.id}_comments`)
#
# Works with @hotwired/turbo.

require 'ruby2js'

module Ruby2JS
  module Filter
    module Turbo
      include SEXP
      extend SEXP

      # Turbo Stream actions
      TURBO_STREAM_ACTIONS = Set.new(%i[
        append
        prepend
        replace
        update
        remove
        before
        after
      ])

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

        # turbo_stream_from "channel_name" - subscribe to broadcast channel
        if target.nil? && method == :turbo_stream_from
          return process_turbo_stream_from(args)
        end

        # turbo_stream.replace, turbo_stream.append, etc.
        if target&.type == :send && target.children == [nil, :turbo_stream]
          if TURBO_STREAM_ACTIONS.include?(method)
            return process_turbo_stream_action(method, args)
          end
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

      # Process turbo_stream action helpers
      # turbo_stream.replace "target", html: content
      # turbo_stream.append "target", partial: "items/item", locals: { item: @item }
      # turbo_stream.remove "target"
      def process_turbo_stream_action(action, args)
        # First arg is the target (string or symbol)
        target_node = args[0]
        target_value = case target_node&.type
          when :str then target_node.children[0]
          when :sym then target_node.children[0].to_s
          else nil  # Dynamic target
        end

        # For remove action, no content needed
        if action == :remove
          if target_value
            return s(:str, "<turbo-stream action=\"remove\" target=\"#{target_value}\"></turbo-stream>")
          else
            # Dynamic target - use template literal
            return s(:dstr,
              s(:str, '<turbo-stream action="remove" target="'),
              s(:begin, process(target_node)),
              s(:str, '"></turbo-stream>'))
          end
        end

        # Get content from options hash
        content_node = nil
        if args[1]&.type == :hash
          args[1].children.each do |pair|
            key_node, value_node = pair.children
            key = key_node.children[0].to_s
            if key == 'html' || key == 'content'
              content_node = value_node
              break
            end
            # For partial/locals, we'd need to render - for now just use the value
            if key == 'partial'
              content_node = value_node
              break
            end
          end
        end

        # Build the turbo-stream element
        if target_value && content_node.nil?
          # Static target, no content (empty template)
          s(:str, "<turbo-stream action=\"#{action}\" target=\"#{target_value}\"><template></template></turbo-stream>")
        elsif target_value && content_node
          # Static target, with content
          processed_content = process(content_node)
          s(:dstr,
            s(:str, "<turbo-stream action=\"#{action}\" target=\"#{target_value}\"><template>"),
            s(:begin, processed_content),
            s(:str, '</template></turbo-stream>'))
        else
          # Dynamic target
          processed_target = process(target_node)
          if content_node
            processed_content = process(content_node)
            s(:dstr,
              s(:str, "<turbo-stream action=\"#{action}\" target=\""),
              s(:begin, processed_target),
              s(:str, '"><template>'),
              s(:begin, processed_content),
              s(:str, '</template></turbo-stream>'))
          else
            s(:dstr,
              s(:str, "<turbo-stream action=\"#{action}\" target=\""),
              s(:begin, processed_target),
              s(:str, '"><template></template></turbo-stream>'))
          end
        end
      end

      # Process turbo_stream_from helper
      # turbo_stream_from "channel_name"
      # turbo_stream_from "article_#{@article.id}_comments"
      #
      # Generates a call to TurboBroadcast.subscribe() which sets up
      # a BroadcastChannel listener that renders incoming turbo-stream messages.
      def process_turbo_stream_from(args)
        return super if args.empty?

        channel_node = args[0]

        # Generate: TurboBroadcast.subscribe("channel_name")
        s(:send,
          s(:const, nil, :TurboBroadcast),
          :subscribe,
          process(channel_node))
      end

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
