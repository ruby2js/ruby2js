require 'ruby2js'

# Phlex filter for Ruby2JS
#
# Transforms Phlex component classes into JavaScript render functions.
# This is an ERB-replacement level implementation - components generate
# HTML strings but do not support component composition.
#
# Status: BETA
#
# Supported features:
# - HTML5 elements (void and standard)
# - Static and dynamic attributes
# - Nested elements
# - Loops (@items.each { |item| ... })
# - Conditionals (if/unless)
# - Instance variables as destructured parameters
# - Special methods: plain, unsafe_raw, whitespace, comment, doctype
#
# Detection:
# - Classes inheriting from Phlex::HTML or Phlex::SVG
# - Classes with `# @ruby2js phlex` pragma (for indirect inheritance)
#
# Limitations (planned for future):
# - Component composition (render OtherComponent.new)
# - Slots
# - Streaming
#
# Example:
#   class CardComponent < Phlex::HTML
#     def initialize(title:)
#       @title = title
#     end
#
#     def view_template
#       div(class: "card") do
#         h1 { @title }
#       end
#     end
#   end
#
# Outputs:
#   class CardComponent {
#     render({ title }) {
#       let _phlex_out = "";
#       _phlex_out += `<div class="card">`;
#       _phlex_out += `<h1>${String(title)}</h1>`;
#       _phlex_out += `</div>`;
#       return _phlex_out;
#     }
#   }

module Ruby2JS
  module Filter
    module Phlex
      include SEXP

      # HTML5 void elements (self-closing)
      VOID_ELEMENTS = %i[
        area base br col embed hr img input link meta param source track wbr
      ].freeze

      # Standard HTML5 elements
      HTML_ELEMENTS = %i[
        a abbr address article aside audio b bdi bdo blockquote body button
        canvas caption cite code colgroup data datalist dd del details dfn
        dialog div dl dt em fieldset figcaption figure footer form h1 h2 h3
        h4 h5 h6 head header hgroup html i iframe ins kbd label legend li
        main map mark menu meter nav noscript object ol optgroup option
        output p picture pre progress q rp rt ruby s samp script section
        select slot small span strong style sub summary sup table tbody td
        template textarea tfoot th thead time title tr u ul var video
      ].freeze

      ALL_ELEMENTS = (VOID_ELEMENTS + HTML_ELEMENTS).freeze

      # Phlex special methods
      PHLEX_METHODS = %i[
        plain unsafe_raw whitespace comment doctype
      ].freeze

      def initialize(*args)
        @phlex_context = false
        @phlex_buffer = nil
        @phlex_ivars = nil
        super
      end

      # Detect Phlex component class definition
      def on_class(node)
        name, parent, body = node.children

        # Check if this should be treated as a Phlex component
        if phlex_component?(node, parent)
          @phlex_context = true
          @phlex_ivars = Set.new

          # Collect all instance variables used in the class
          collect_ivars(body)

          result = super
          @phlex_context = false
          @phlex_ivars = nil
          return result
        end

        super
      end

      # Handle method definitions within Phlex context
      def on_def(node)
        return super unless @phlex_context

        method_name, args, body = node.children

        # Transform view_template or template method to render
        if [:view_template, :template].include?(method_name)
          @phlex_buffer = :_phlex_out

          # Build destructured parameters from collected ivars
          if @phlex_ivars && !@phlex_ivars.empty?
            kwargs = @phlex_ivars.to_a.sort.map do |ivar|
              prop_name = ivar.to_s[1..-1].to_sym  # @title -> title
              s(:kwarg, prop_name)
            end
            render_args = s(:args, *kwargs)
          else
            render_args = s(:args)
          end

          # Transform the body
          transformed_body = process(body)

          # Wrap in buffer initialization and return
          init = s(:lvasgn, @phlex_buffer, s(:str, ''))
          ret = s(:return, s(:lvar, @phlex_buffer))

          new_body = if transformed_body
            s(:begin, init, transformed_body, ret)
          else
            s(:begin, init, ret)
          end

          result = s(:def, :render, render_args, new_body)
          @phlex_buffer = nil
          return result
        end

        # Skip initialize method (ivars become render params instead)
        if method_name == :initialize
          return nil
        end

        super
      end

      # Convert instance variable reads to local variable reads
      def on_ivar(node)
        return super unless @phlex_buffer

        ivar_name = node.children.first
        prop_name = ivar_name.to_s[1..-1].to_sym  # @title -> title
        s(:lvar, prop_name)
      end

      # Handle pnode (synthetic AST node for elements)
      # Structure: s(:pnode, tag, attrs_hash, *children)
      def on_pnode(node)
        return super unless @phlex_buffer

        tag, attrs, *children = node.children

        process_pnode_element(tag, attrs, children)
      end

      # Handle pnode_text (text content in pnode)
      # Structure: s(:pnode_text, content_node)
      def on_pnode_text(node)
        return super unless @phlex_buffer

        content = node.children.first

        if content.type == :str
          # Static text - add directly
          s(:op_asgn, s(:lvasgn, @phlex_buffer), :+, content)
        else
          # Dynamic content - stringify
          s(:op_asgn, s(:lvasgn, @phlex_buffer), :+,
            s(:send, nil, :String, process(content)))
        end
      end

      # Handle element method calls
      def on_send(node)
        return super unless @phlex_buffer

        target, method, *args = node.children

        # Only handle calls with no receiver (element methods)
        return super unless target.nil?

        if ALL_ELEMENTS.include?(method)
          return process_element(method, args, nil)
        end

        if PHLEX_METHODS.include?(method)
          return process_phlex_method(method, args)
        end

        # Handle render Component.new(...) for component composition
        if method == :render && args.first&.type == :send
          component_call = args.first
          if component_call.children[1] == :new
            return process_component(component_call, nil)
          end
        end

        # Handle tag("custom-element", ...) for custom elements
        if method == :tag && args.first&.type == :str
          tag_name = args.first.children.first
          tag_args = args[1..-1]
          return process_custom_element(tag_name, tag_args, nil)
        end

        # Handle fragment (for pnode nil tag)
        if method == :fragment
          return nil  # Fragment produces no output itself
        end

        super
      end

      # Handle element calls with blocks (including loops)
      def on_block(node)
        return super unless @phlex_buffer

        send_node, block_args, block_body = node.children

        return super unless send_node.type == :send

        target, method, *args = send_node.children

        # Handle element with block (div { ... })
        if target.nil? && ALL_ELEMENTS.include?(method)
          return process_element(method, args, block_body)
        end

        # Handle render Component.new do ... end
        if target.nil? && method == :render && args.first&.type == :send
          component_call = args.first
          if component_call.children[1] == :new
            return process_component(component_call, block_body)
          end
        end

        # Handle tag("custom-element") do ... end
        if target.nil? && method == :tag && args.first&.type == :str
          tag_name = args.first.children.first
          tag_args = args[1..-1]
          return process_custom_element(tag_name, tag_args, block_body)
        end

        # Handle fragment do ... end
        if target.nil? && method == :fragment
          # Fragment just processes children without wrapper
          return process_fragment(block_body)
        end

        # For loops (.each, .map, etc.), let other filters handle the conversion
        # but ensure the body is processed for Phlex elements
        super
      end

      # Handle conditionals
      def on_if(node)
        return super unless @phlex_buffer

        # Process normally - Ruby2JS handles if/unless conversion
        # We just need to make sure the body is processed for elements
        condition, if_body, else_body = node.children

        processed_condition = process(condition)
        processed_if = if_body ? process(if_body) : nil
        processed_else = else_body ? process(else_body) : nil

        s(:if, processed_condition, processed_if, processed_else)
      end

      private

      def phlex_component?(node, parent)
        # Direct inheritance from Phlex::HTML or Phlex::SVG
        return true if phlex_parent?(parent)

        # Check for pragma: # @ruby2js phlex
        # This enables Phlex transformation for indirect inheritance:
        #   # @ruby2js phlex
        #   class Card < ApplicationComponent
        raw_comments = @comments[:_raw] || []
        class_line = node.loc&.line rescue nil

        raw_comments.any? do |comment|
          text = comment.respond_to?(:text) ? comment.text : comment.to_s
          comment_line = (comment.loc&.line rescue nil)

          # Check if comment contains the pragma and is near the class definition
          if text.include?('@ruby2js phlex')
            # Pragma on line immediately before or same line as class
            class_line.nil? || comment_line.nil? ||
              (comment_line >= class_line - 1 && comment_line <= class_line)
          else
            false
          end
        end
      end

      def phlex_parent?(node)
        return false unless node

        # Check for Phlex::HTML or Phlex::SVG
        if node.type == :const
          parent, name = node.children
          if parent&.type == :const && parent.children == [nil, :Phlex]
            return [:HTML, :SVG].include?(name)
          end
        end

        false
      end

      # Recursively collect all instance variables in the AST
      def collect_ivars(node)
        return unless node.respond_to?(:type)

        if node.type == :ivar
          @phlex_ivars << node.children.first
        end

        node.children.each do |child|
          collect_ivars(child) if child.respond_to?(:type)
        end
      end

      def process_element(tag, args, block_body)
        tag_str = tag.to_s
        void = VOID_ELEMENTS.include?(tag)

        # Extract attributes hash if present
        attrs_node = args.find { |a| a.respond_to?(:type) && a.type == :hash }

        statements = []

        # Build the opening tag (may be dynamic if has dynamic attrs)
        open_tag = build_open_tag(tag_str, attrs_node)
        statements << s(:op_asgn, s(:lvasgn, @phlex_buffer), :+, open_tag)

        # Process block content for non-void elements
        unless void
          if block_body
            content = process_block_content(block_body)
            statements.concat(content) if content&.any?
          end

          # Add closing tag
          close_tag = s(:str, "</#{tag_str}>")
          statements << s(:op_asgn, s(:lvasgn, @phlex_buffer), :+, close_tag)
        end

        statements.length == 1 ? statements.first : s(:begin, *statements)
      end

      def build_open_tag(tag_str, attrs_node)
        return s(:str, "<#{tag_str}>") unless attrs_node&.type == :hash

        static_attrs = []
        dynamic_attrs = []

        attrs_node.children.each do |pair|
          next unless pair.type == :pair

          key_node, value_node = pair.children

          # Get the attribute name
          key = case key_node.type
          when :sym then key_node.children.first.to_s
          when :str then key_node.children.first
          else next
          end

          # Handle special attribute names
          key = 'class' if key == 'class_name'
          key = key.tr('_', '-') # data_foo -> data-foo

          # Categorize as static or dynamic
          case value_node.type
          when :str
            value = value_node.children.first
            static_attrs << "#{key}=\"#{escape_html(value)}\""
          when :sym
            value = value_node.children.first.to_s
            static_attrs << "#{key}=\"#{escape_html(value)}\""
          when :true
            static_attrs << key
          when :false
            # Skip false boolean attributes
          else
            # Dynamic value
            dynamic_attrs << [key, value_node]
          end
        end

        # If no dynamic attributes, return simple string
        if dynamic_attrs.empty?
          attrs_str = static_attrs.empty? ? '' : ' ' + static_attrs.join(' ')
          return s(:str, "<#{tag_str}#{attrs_str}>")
        end

        # Build template literal with interpolation for dynamic values
        # `<tag static="val" dynamic="${expr}">`
        parts = ["<#{tag_str}"]
        parts << ' ' + static_attrs.join(' ') unless static_attrs.empty?

        dynamic_attrs.each do |key, value_node|
          parts << " #{key}=\""
          # Close current string, add interpolation, continue
        end

        # For dynamic attributes, we need dstr (interpolated string)
        children = []
        children << s(:str, "<#{tag_str}")
        children << s(:str, ' ' + static_attrs.join(' ')) unless static_attrs.empty?

        dynamic_attrs.each do |key, value_node|
          children << s(:str, " #{key}=\"")
          children << s(:begin, process(value_node))
          children << s(:str, '"')
        end

        children << s(:str, '>')

        s(:dstr, *children)
      end

      def process_block_content(node)
        return [] unless node

        statements = []

        case node.type
        when :begin
          node.children.each do |child|
            result = process_content_node(child)
            if result.is_a?(Array)
              statements.concat(result)
            elsif result
              statements << result
            end
          end
        else
          result = process_content_node(node)
          if result.is_a?(Array)
            statements.concat(result)
          elsif result
            statements << result
          end
        end

        statements
      end

      def process_content_node(node)
        return nil unless node

        case node.type
        when :str
          # String literal content
          s(:op_asgn, s(:lvasgn, @phlex_buffer), :+, node)
        when :dstr
          # Interpolated string
          s(:op_asgn, s(:lvasgn, @phlex_buffer), :+, process(node))
        when :ivar
          # Instance variable - convert to local and stringify
          prop_name = node.children.first.to_s[1..-1].to_sym
          s(:op_asgn, s(:lvasgn, @phlex_buffer), :+,
            s(:send, nil, :String, s(:lvar, prop_name)))
        when :lvar
          # Local variable - stringify
          s(:op_asgn, s(:lvasgn, @phlex_buffer), :+,
            s(:send, nil, :String, node))
        when :send
          target, method, *args = node.children
          if target.nil? && ALL_ELEMENTS.include?(method)
            # Nested element without block
            [process_element(method, args, nil)]
          elsif target.nil? && PHLEX_METHODS.include?(method)
            [process_phlex_method(method, args)]
          else
            # Other method call - process and add to buffer if it returns something
            processed = process(node)
            s(:op_asgn, s(:lvasgn, @phlex_buffer), :+,
              s(:send, nil, :String, processed))
          end
        when :block
          # Could be nested element with block or a loop
          processed = process(node)
          [processed].compact
        when :if
          # Conditional - process it
          [process(node)]
        else
          processed = process(node)
          [processed].compact
        end
      end

      def process_phlex_method(method, args)
        case method
        when :plain
          # plain "text" or plain variable - stringify and add
          arg = args.first
          if arg
            s(:op_asgn, s(:lvasgn, @phlex_buffer), :+,
              s(:send, nil, :String, process(arg)))
          end
        when :unsafe_raw
          # unsafe_raw "html" - add without escaping or String()
          arg = args.first
          if arg
            s(:op_asgn, s(:lvasgn, @phlex_buffer), :+, process(arg))
          end
        when :whitespace
          s(:op_asgn, s(:lvasgn, @phlex_buffer), :+, s(:str, ' '))
        when :comment
          arg = args.first
          if arg
            if arg.type == :str
              text = arg.children.first
              s(:op_asgn, s(:lvasgn, @phlex_buffer), :+,
                s(:str, "<!-- #{text} -->"))
            else
              # Dynamic comment
              s(:op_asgn, s(:lvasgn, @phlex_buffer), :+,
                s(:dstr,
                  s(:str, '<!-- '),
                  s(:begin, process(arg)),
                  s(:str, ' -->')))
            end
          end
        when :doctype
          s(:op_asgn, s(:lvasgn, @phlex_buffer), :+,
            s(:str, '<!DOCTYPE html>'))
        end
      end

      # Process a pnode (synthetic AST node for elements)
      def process_pnode_element(tag, attrs, children)
        statements = []

        case tag
        when nil
          # Fragment - just process children
          children.each do |child|
            result = process(child)
            statements << result if result
          end
        when Symbol
          if tag.to_s[0] =~ /[A-Z]/
            # Component (uppercase)
            statements << process_pnode_component(tag, attrs, children)
          else
            # HTML element (lowercase)
            statements.concat(process_pnode_html_element(tag, attrs, children))
          end
        when String
          # Custom element
          statements.concat(process_pnode_custom_element(tag, attrs, children))
        end

        statements.length == 1 ? statements.first : s(:begin, *statements)
      end

      def process_pnode_html_element(tag, attrs, children)
        tag_str = tag.to_s
        void = VOID_ELEMENTS.include?(tag)
        statements = []

        # Build open tag
        open_tag = build_open_tag(tag_str, attrs)
        statements << s(:op_asgn, s(:lvasgn, @phlex_buffer), :+, open_tag)

        # Process children for non-void elements
        unless void
          children.each do |child|
            result = process(child)
            statements << result if result
          end

          # Close tag
          statements << s(:op_asgn, s(:lvasgn, @phlex_buffer), :+,
            s(:str, "</#{tag_str}>"))
        end

        statements
      end

      def process_pnode_component(tag, attrs, children)
        component_name = tag.to_s

        # Build props hash from attrs
        props = []
        if attrs&.type == :hash
          attrs.children.each do |pair|
            next unless pair.type == :pair
            props << pair
          end
        end

        # Build render call: ComponentName.render({ props }, () => { children })
        props_hash = props.empty? ? s(:hash) : s(:hash, *props)

        if children.empty?
          # No children: ComponentName.render({ props })
          s(:op_asgn, s(:lvasgn, @phlex_buffer), :+,
            s(:send, s(:const, nil, tag), :render, process(props_hash)))
        else
          # With children: ComponentName.render({ props }, () => { ... })
          child_statements = children.map { |c| process(c) }.compact
          child_body = child_statements.length == 1 ? child_statements.first : s(:begin, *child_statements)

          s(:op_asgn, s(:lvasgn, @phlex_buffer), :+,
            s(:send, s(:const, nil, tag), :render,
              process(props_hash),
              s(:block, s(:send, nil, :proc), s(:args), child_body)))
        end
      end

      def process_pnode_custom_element(tag, attrs, children)
        statements = []

        # Build open tag
        open_tag = build_open_tag(tag, attrs)
        statements << s(:op_asgn, s(:lvasgn, @phlex_buffer), :+, open_tag)

        # Process children
        children.each do |child|
          result = process(child)
          statements << result if result
        end

        # Close tag
        statements << s(:op_asgn, s(:lvasgn, @phlex_buffer), :+,
          s(:str, "</#{tag}>"))

        statements
      end

      # Process render Component.new(...) for component composition
      def process_component(component_call, block_body)
        component_const = component_call.children[0]
        component_args = component_call.children[2..-1] || []

        # Extract props hash
        props_hash = component_args.find { |a| a.respond_to?(:type) && a.type == :hash }
        props_hash = props_hash ? process(props_hash) : s(:hash)

        if block_body
          # With children: Component.render({ props }, () => { ... })
          child_content = process_block_content(block_body)
          child_body = child_content.length == 1 ? child_content.first : s(:begin, *child_content)

          s(:op_asgn, s(:lvasgn, @phlex_buffer), :+,
            s(:send, component_const, :render,
              props_hash,
              s(:block, s(:send, nil, :proc), s(:args), child_body)))
        else
          # No children: Component.render({ props })
          s(:op_asgn, s(:lvasgn, @phlex_buffer), :+,
            s(:send, component_const, :render, props_hash))
        end
      end

      # Process tag("custom-element", ...) for custom elements
      def process_custom_element(tag_name, args, block_body)
        # Extract attrs hash
        attrs_node = args.find { |a| a.respond_to?(:type) && a.type == :hash }

        statements = []

        # Build open tag
        open_tag = build_open_tag(tag_name, attrs_node)
        statements << s(:op_asgn, s(:lvasgn, @phlex_buffer), :+, open_tag)

        # Process block content if present
        if block_body
          content = process_block_content(block_body)
          statements.concat(content) if content&.any?
        end

        # Close tag
        statements << s(:op_asgn, s(:lvasgn, @phlex_buffer), :+,
          s(:str, "</#{tag_name}>"))

        statements.length == 1 ? statements.first : s(:begin, *statements)
      end

      # Process fragment do ... end
      def process_fragment(block_body)
        return nil unless block_body

        content = process_block_content(block_body)
        return nil if content.empty?

        content.length == 1 ? content.first : s(:begin, *content)
      end

      def escape_html(str)
        str.to_s
          .gsub('&', '&amp;')
          .gsub('<', '&lt;')
          .gsub('>', '&gt;')
          .gsub('"', '&quot;')
      end
    end

    DEFAULTS.push Phlex
  end
end
