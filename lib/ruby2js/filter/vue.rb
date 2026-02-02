require 'ruby2js'

module Ruby2JS
  module Filter
    module Vue
      include SEXP
      extend  SEXP

      def initialize(node)
        super
        @vue_mode = false
        @vue_props = []
      end

      def options=(options)
        super
        # Detect if Phlex filter is present for Phlex → Vue compilation
        filters = options[:filters] || Filter::DEFAULTS
        if defined?(Ruby2JS::Filter::Phlex) && filters.include?(Ruby2JS::Filter::Phlex)
          @vue_mode = true
        end
      end

      # Intercept the entire class to transform into Vue SFC format
      def on_class(node)
        return super unless @vue_mode

        # Process the class first to get pnodes
        processed = super

        # Check if this is a Phlex class (processed will have render method with pnodes)
        return processed unless processed.type == :class

        name, parent, body = processed.children
        return processed unless body

        # Find the render method
        methods = body.type == :begin ? body.children : [body]
        render_method = methods.find { |m| m&.type == :def && m.children.first == :render }

        return processed unless render_method

        # Extract props and template from render method
        _, args, render_body = render_method.children

        # Get props from destructured args
        @vue_props = extract_props(args)

        # Extract template content from render body
        template_content = extract_template(render_body)

        # Build script section
        script_content = build_script

        # Return vue_file node
        s(:vue_file, script_content, template_content)
      end

      # Handle pnode (from Phlex filter) - convert to Vue template
      def on_pnode(node)
        return super unless @vue_mode

        tag, attrs, *children = node.children

        # Build the template content
        template_parts = build_vue_template(tag, attrs, children)
        template_content = template_parts.join('')

        # Return a special node that the parent can use
        s(:vue_template, template_content)
      end

      # Handle pnode_text (from Phlex filter)
      def on_pnode_text(node)
        return super unless @vue_mode
        node
      end

      private

      def extract_props(args)
        return [] unless args&.type == :args

        props = []
        args.children.each do |arg|
          case arg.type
          when :kwarg, :kwoptarg
            props << arg.children.first.to_s
          end
        end
        props
      end

      def extract_template(body)
        return '' unless body

        case body.type
        when :vue_template
          body.children.first
        when :pnode
          # Process the pnode to get template
          tag, attrs, *children = body.children
          build_vue_template(tag, attrs, children).join('')
        when :return
          extract_template(body.children.first)
        when :begin
          # Multiple statements - find the pnode or vue_template
          body.children.map { |c| extract_template(c) }.join('')
        else
          ''
        end
      end

      def build_script
        return '' if @vue_props.empty?
        "defineProps(['#{@vue_props.join("', '")}'])"
      end

      # Build template parts for a pnode
      def build_vue_template(tag, attrs, children)
        parts = []

        if tag.nil?
          # Fragment - just children
          # Note: Use push with splat instead of concat for JS compatibility
          children.each do |child|
            parts.push(*build_vue_child(child))
          end
        elsif tag.to_s[0] =~ /[A-Z]/
          # Component - render as Vue component
          parts << build_component_element(tag, attrs, children)
        else
          # HTML element
          parts << build_html_element(tag, attrs, children)
        end

        parts
      end

      def build_component_element(tag, attrs, children)
        tag_str = tag.to_s

        if children.empty?
          if attrs.nil? || (attrs.type == :hash && attrs.children.empty?)
            "<#{tag_str} />"
          else
            "<#{tag_str}#{build_vue_attrs(attrs)} />"
          end
        else
          child_content = children.map { |c| build_vue_child(c) }.flatten.join('')
          "<#{tag_str}#{build_vue_attrs(attrs)}>#{child_content}</#{tag_str}>"
        end
      end

      def build_html_element(tag, attrs, children)
        tag_str = tag.to_s
        void_elements = %i[area base br col embed hr img input link meta param source track wbr]

        if void_elements.include?(tag_str.to_sym)
          "<#{tag_str}#{build_vue_attrs(attrs)} />"
        elsif children.empty?
          "<#{tag_str}#{build_vue_attrs(attrs)}></#{tag_str}>"
        else
          child_content = children.map { |c| build_vue_child(c) }.flatten.join('')
          "<#{tag_str}#{build_vue_attrs(attrs)}>#{child_content}</#{tag_str}>"
        end
      end

      def build_vue_child(child)
        parts = []

        # Handle already processed AST nodes (like :lvar for props)
        unless child.respond_to?(:type)
          parts << child.to_s
          return parts
        end

        case child.type
        when :pnode_text
          content = child.children.first
          if content.type == :str
            parts << content.children.first
          else
            # Vue uses {{ }} for interpolation
            parts << "{{ #{expr_to_js(content)} }}"
          end
        when :pnode
          tag, attrs, *grandchildren = child.children
          # Note: Use push with splat instead of concat for JS compatibility
          parts.push(*build_vue_template(tag, attrs, grandchildren))
        when :vue_template
          parts << child.children.first
        when :block
          # Loop - convert to v-for
          parts << build_vue_loop(child)
        when :if
          # Conditional - convert to v-if
          parts << build_vue_conditional(child)
        when :str
          parts << child.children.first
        else
          # Other expression - wrap in {{ }}
          parts << "{{ #{expr_to_js(child)} }}"
        end
        parts
      end

      def build_vue_attrs(attrs)
        return '' unless attrs&.respond_to?(:type) && attrs.type == :hash

        result = ''
        attrs.children.each do |pair|
          next unless pair.type == :pair
          key_node, value_node = pair.children

          key = case key_node.type
          when :sym then key_node.children.first.to_s
          when :str then key_node.children.first
          else next
          end

          # Convert underscores to dashes for data/aria attributes
          key = key.gsub('_', '-') if key.start_with?('data_', 'aria_')

          # Handle event handlers (on_click -> @click)
          if key.start_with?('on_')
            event_name = key[3..-1]  # Remove 'on_'
            result += " @#{event_name}=\"#{expr_to_js(value_node)}\""
          else
            case value_node.type
            when :str
              result += " #{key}=\"#{value_node.children.first.gsub('"', '&quot;')}\""
            when :sym
              result += " #{key}=\"#{value_node.children.first}\""
            when :true
              result += " #{key}"
            when :false
              # Skip false boolean attributes
            else
              # Dynamic value - use v-bind shorthand (:attr)
              result += " :#{key}=\"#{expr_to_js(value_node)}\""
            end
          end
        end
        result
      end

      def build_vue_loop(block_node)
        send_node, block_args, block_body = block_node.children
        return "<!-- loop -->" unless send_node.type == :send

        target, method, *args = send_node.children

        # Get loop variable
        loop_var = block_args.children.first&.children&.first || 'item'

        # Build the body - should be a single element with v-for
        if block_body.respond_to?(:type) && block_body.type == :pnode
          tag, attrs, *children = block_body.children

          # Add v-for to the element's attributes
          target_js = expr_to_js(target)
          v_for_attr = " v-for=\"#{loop_var} in #{target_js}\""

          tag_str = tag.to_s
          existing_attrs = build_vue_attrs(attrs)
          child_content = children.map { |c| build_vue_child(c) }.flatten.join('')

          "<#{tag_str}#{v_for_attr}#{existing_attrs}>#{child_content}</#{tag_str}>"
        elsif block_body.respond_to?(:type) && block_body.type == :vue_template
          # Already processed - wrap in template with v-for
          target_js = expr_to_js(target)
          "<template v-for=\"#{loop_var} in #{target_js}\">#{block_body.children.first}</template>"
        else
          "<!-- loop: #{expr_to_js(block_body)} -->"
        end
      end

      def build_vue_conditional(if_node)
        condition, then_branch, else_branch = if_node.children

        # Build condition expression
        cond_js = expr_to_js(condition)

        if then_branch.respond_to?(:type) && then_branch.type == :pnode
          tag, attrs, *children = then_branch.children

          tag_str = tag.to_s
          v_if_attr = " v-if=\"#{cond_js}\""
          existing_attrs = build_vue_attrs(attrs)
          child_content = children.map { |c| build_vue_child(c) }.flatten.join('')

          result = "<#{tag_str}#{v_if_attr}#{existing_attrs}>#{child_content}</#{tag_str}>"

          # Handle else branch if present
          if else_branch
            result += build_vue_else(else_branch)
          end

          result
        else
          "<template v-if=\"#{cond_js}\">#{extract_template(then_branch)}</template>"
        end
      end

      def build_vue_else(else_branch)
        if else_branch.respond_to?(:type) && else_branch.type == :pnode
          tag, attrs, *children = else_branch.children

          tag_str = tag.to_s
          existing_attrs = build_vue_attrs(attrs)
          child_content = children.map { |c| build_vue_child(c) }.flatten.join('')

          "<#{tag_str} v-else#{existing_attrs}>#{child_content}</#{tag_str}>"
        else
          "<template v-else>#{extract_template(else_branch)}</template>"
        end
      end

      def expr_to_js(node)
        return node.to_s unless node.respond_to?(:type)

        # Convert AST node to JavaScript expression string
        case node.type
        when :lvar
          node.children.first.to_s
        when :ivar
          prop_name = node.children.first.to_s[1..-1]
          @vue_props << prop_name unless @vue_props.include?(prop_name)
          prop_name
        when :send
          target, method, *args = node.children
          if target.nil?
            if args.empty?
              method.to_s
            else
              "#{method}(#{args.map { |a| expr_to_js(a) }.join(', ')})"
            end
          else
            if args.empty?
              "#{expr_to_js(target)}.#{method}"
            else
              "#{expr_to_js(target)}.#{method}(#{args.map { |a| expr_to_js(a) }.join(', ')})"
            end
          end
        when :str
          "\"#{node.children.first.gsub('"', '\\"')}\""
        when :int, :float
          node.children.first.to_s
        when :true
          'true'
        when :false
          'false'
        when :nil
          'null'
        when :const
          if node.children.first.nil?
            node.children.last.to_s
          else
            "#{expr_to_js(node.children.first)}.#{node.children.last}"
          end
        when :array
          "[#{node.children.map { |c| expr_to_js(c) }.join(', ')}]"
        when :hash
          pairs = node.children.map do |pair|
            if pair.type == :pair
              k, v = pair.children
              key_str = k.type == :sym ? k.children.first.to_s : expr_to_js(k)
              "#{key_str}: #{expr_to_js(v)}"
            end
          end.compact
          "{#{pairs.join(', ')}}"
        else
          # Fallback - use the node's string representation
          node.to_s
        end
      end
    end

    DEFAULTS.push Vue
  end
end
