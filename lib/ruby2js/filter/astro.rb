require 'ruby2js'

module Ruby2JS
  module Filter
    module Astro
      include SEXP
      extend  SEXP

      def initialize(node)
        super
        @astro_mode = false
        @astro_props = []
      end

      def options=(options)
        super
        # Detect if Phlex filter is present for Phlex → Astro compilation
        filters = options[:filters] || Filter::DEFAULTS
        if defined?(Ruby2JS::Filter::Phlex) && filters.include?(Ruby2JS::Filter::Phlex)
          @astro_mode = true
        end
      end

      # Intercept the entire class to transform into Astro format
      def on_class(node)
        return super unless @astro_mode

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
        @astro_props = extract_props(args)

        # Extract template content from render body
        template_content = extract_template(render_body)

        # Build frontmatter
        frontmatter = build_frontmatter

        # Return astro_file node
        s(:astro_file, frontmatter, template_content)
      end

      # Handle pnode (from Phlex filter) - convert to Astro template
      def on_pnode(node)
        return super unless @astro_mode

        tag, attrs, *children = node.children

        # Build the template content
        template_parts = build_astro_template(tag, attrs, children)
        template_content = template_parts.join('')

        # Return a special node that the parent can use
        s(:astro_template, template_content)
      end

      # Handle pnode_text (from Phlex filter)
      def on_pnode_text(node)
        return super unless @astro_mode
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
        when :astro_template
          body.children.first
        when :pnode
          # Process the pnode to get template
          tag, attrs, *children = body.children
          build_astro_template(tag, attrs, children).join('')
        when :return
          extract_template(body.children.first)
        when :begin
          # Multiple statements - find the pnode or astro_template
          body.children.map { |c| extract_template(c) }.join('')
        else
          ''
        end
      end

      def build_frontmatter
        return '' if @astro_props.empty?
        "const { #{@astro_props.join(', ')} } = Astro.props;"
      end

      # Build template parts for a pnode
      def build_astro_template(tag, attrs, children)
        parts = []

        if tag.nil?
          # Fragment - just children
          children.each do |child|
            parts.concat(build_astro_child(child))
          end
        elsif tag.to_s[0] =~ /[A-Z]/
          # Component - render as JSX element
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
            "<#{tag_str}#{build_astro_attrs(attrs)} />"
          end
        else
          child_content = children.map { |c| build_astro_child(c) }.flatten.join('')
          "<#{tag_str}#{build_astro_attrs(attrs)}>#{child_content}</#{tag_str}>"
        end
      end

      def build_html_element(tag, attrs, children)
        tag_str = tag.to_s
        void_elements = %i[area base br col embed hr img input link meta param source track wbr]

        if void_elements.include?(tag_str.to_sym)
          "<#{tag_str}#{build_astro_attrs(attrs)} />"
        elsif children.empty?
          "<#{tag_str}#{build_astro_attrs(attrs)}></#{tag_str}>"
        else
          child_content = children.map { |c| build_astro_child(c) }.flatten.join('')
          "<#{tag_str}#{build_astro_attrs(attrs)}>#{child_content}</#{tag_str}>"
        end
      end

      def build_astro_child(child)
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
            parts << "{#{expr_to_js(content)}}"
          end
        when :pnode
          tag, attrs, *grandchildren = child.children
          parts.concat(build_astro_template(tag, attrs, grandchildren))
        when :astro_template
          parts << child.children.first
        when :block
          # Loop - convert to .map()
          parts << build_astro_loop(child)
        when :for, :for_of
          # Converted loop
          parts << build_astro_for_loop(child)
        when :str
          parts << child.children.first
        else
          # Other expression - wrap in {}
          parts << "{#{expr_to_js(child)}}"
        end
        parts
      end

      def build_astro_attrs(attrs)
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

          # Convert class to class (Astro uses standard HTML class)
          # Convert underscores to dashes for data attributes
          key = key.gsub('_', '-') if key.start_with?('data_', 'aria_')

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
            # Dynamic value
            result += " #{key}={#{expr_to_js(value_node)}}"
          end
        end
        result
      end

      def build_astro_loop(block_node)
        send_node, block_args, block_body = block_node.children
        return "{/* loop */}" unless send_node.type == :send

        target, method, *args = send_node.children

        # Build the body
        body_content = if block_body.respond_to?(:type) && block_body.type == :pnode
          tag, attrs, *children = block_body.children
          build_astro_template(tag, attrs, children).join('')
        elsif block_body.respond_to?(:type) && block_body.type == :astro_template
          block_body.children.first
        else
          "{#{expr_to_js(block_body)}}"
        end

        # Get loop variable
        loop_var = block_args.children.first&.children&.first || 'item'

        # Return array.map(x => ...) expression
        target_js = expr_to_js(target)
        "{#{target_js}.map(#{loop_var} => #{body_content})}"
      end

      def build_astro_for_loop(for_node)
        # For now, process as expression
        "{/* for loop */}"
      end

      def expr_to_js(node)
        return node.to_s unless node.respond_to?(:type)

        # Convert AST node to JavaScript expression string
        case node.type
        when :lvar
          node.children.first.to_s
        when :ivar
          prop_name = node.children.first.to_s[1..-1]
          @astro_props << prop_name unless @astro_props.include?(prop_name)
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

    DEFAULTS.push Astro
  end
end
