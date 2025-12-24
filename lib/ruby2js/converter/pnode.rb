module Ruby2JS
  class Converter

    # pnode (Phlex node) is a synthetic node representing elements in a unified format.
    #
    # Structure: s(:pnode, tag, attrs_hash, *children)
    #   - tag is nil (fragment), or a string/symbol for element/component name
    #   - Uppercase first char = Component, lowercase = HTML element
    #   - attrs_hash is s(:hash, ...) with attribute pairs
    #   - children are nested pnodes, pnode_text, or other expressions
    #
    # This handler outputs template literal strings for elements.
    # Filters (like React) can intercept pnodes before they reach here.

    # HTML5 void elements (self-closing)
    PNODE_VOID_ELEMENTS = %i[
      area base br col embed hr img input link meta param source track wbr
    ].freeze

    handle :pnode do |tag, attrs, *children|
      if tag.nil?
        # Fragment - just output children
        children.each_with_index do |child, index|
          put @sep if index > 0
          parse child
        end
      else
        tag_str = tag.to_s

        if tag_str[0] =~ /[A-Z]/
          # Component - output as function call: Component.render({ props }, children)
          put tag_str
          put '.render('
          parse_pnode_attrs_as_object(attrs)
          unless children.empty?
            put ', '
            put '() => '
            if children.length == 1
              parse children.first
            else
              put '('
              children.each_with_index do |child, idx|
                put ', ' if idx > 0
                parse child
              end
              put ')'
            end
          end
          put ')'
        else
          # HTML element or custom element - output as template literal
          output_pnode_element(tag_str, attrs, children)
        end
      end
    end

    # pnode_text represents text content within a pnode
    # Structure: s(:pnode_text, content_node)

    handle :pnode_text do |content|
      if content.type == :str
        # Static text - output as string within template literal context
        text = content.children.first
        put text.gsub('`', '\\`').gsub('$', '\\$')
      else
        # Dynamic content - wrap in interpolation
        put '${'
        put 'String('
        parse content
        put ')}'
      end
    end

    private

    def output_pnode_element(tag_str, attrs, children)
      void = PNODE_VOID_ELEMENTS.include?(tag_str.to_sym)
      has_dynamic = pnode_has_dynamic_attrs?(attrs) || pnode_has_dynamic_children?(children)
      has_loops = pnode_has_loops?(children)

      if has_loops
        # Use IIFE to wrap loops (for loops are statements, not expressions)
        # Use _phlex_out as the variable name since loop bodies already use it
        put '(() => {'
        put ' let _phlex_out = `'
        put "<#{tag_str}"
        output_pnode_attrs_in_template(attrs)
        put '>`; '

        unless void
          children.each { |child| output_pnode_child_with_loops(child) }
          put '_phlex_out += `'
          put "</#{tag_str}>"
          put '`; return _phlex_out; '
        else
          put 'return _phlex_out; '
        end
        put '})()'
      elsif has_dynamic
        # Use template literal for dynamic content
        put '`'
        put "<#{tag_str}"
        output_pnode_attrs_in_template(attrs)
        put '>'

        unless void
          children.each { |child| output_pnode_child_inline(child) }
          put "</#{tag_str}>"
        end
        put '`'
      else
        # Use regular string for static content
        put '"'
        put "<#{tag_str}"
        output_pnode_attrs_static(attrs)
        put '>'

        unless void
          children.each do |child|
            output_pnode_child_static(child)
          end
          put "</#{tag_str}>"
        end
        put '"'
      end
    end

    # Output a child node inline within a template literal (no wrapping quotes)
    def output_pnode_child_inline(child)
      case child.type
      when :pnode_text
        content = child.children.first
        if content.type == :str
          text = content.children.first
          put text.gsub('`', '\\`').gsub('$', '\\$')
        else
          put '${String('
          parse content
          put ')}'
        end
      when :pnode
        tag, attrs, *grandchildren = child.children
        output_pnode_inline(tag, attrs, grandchildren)
      else
        # Other expression - wrap in interpolation
        put '${'
        parse child
        put '}'
      end
    end

    # Output a pnode inline (for nesting within template literals)
    def output_pnode_inline(tag, attrs, children)
      if tag.nil?
        # Fragment - just output children
        children.each { |child| output_pnode_child_inline(child) }
      else
        tag_str = tag.to_s
        if tag_str[0] =~ /[A-Z]/
          # Component - wrap in interpolation
          put '${'
          put tag_str
          put '.render('
          parse_pnode_attrs_as_object(attrs)
          put ')}'
        else
          output_pnode_element_inline(tag_str, attrs, children)
        end
      end
    end

    # Output an HTML element inline within a template literal
    def output_pnode_element_inline(tag_str, attrs, children)
      void = PNODE_VOID_ELEMENTS.include?(tag_str.to_sym)

      put "<#{tag_str}"
      output_pnode_attrs_in_template(attrs)
      put '>'

      unless void
        children.each { |child| output_pnode_child_inline(child) }
        put "</#{tag_str}>"
      end
    end

    # Output a child node for static content (within double quotes)
    def output_pnode_child_static(child)
      case child.type
      when :pnode_text
        content = child.children.first
        if content.type == :str
          text = content.children.first
          put text.gsub('"', '\\"')
        else
          # Dynamic content in static context - break out and concatenate
          put '" + String('
          parse content
          put ') + "'
        end
      when :pnode
        tag, attrs, *grandchildren = child.children
        output_pnode_static_inline(tag, attrs, grandchildren)
      else
        # Other expression - break out and concatenate
        put '" + ('
        parse child
        put ') + "'
      end
    end

    # Output a pnode inline for static context
    def output_pnode_static_inline(tag, attrs, children)
      if tag.nil?
        children.each { |child| output_pnode_child_static(child) }
      else
        tag_str = tag.to_s
        if tag_str[0] =~ /[A-Z]/
          put '" + '
          put tag_str
          put '.render('
          parse_pnode_attrs_as_object(attrs)
          put ') + "'
        else
          output_pnode_element_static_inline(tag_str, attrs, children)
        end
      end
    end

    # Output an HTML element inline for static context
    def output_pnode_element_static_inline(tag_str, attrs, children)
      void = PNODE_VOID_ELEMENTS.include?(tag_str.to_sym)

      put "<#{tag_str}"
      output_pnode_attrs_static(attrs)
      put '>'

      unless void
        children.each { |child| output_pnode_child_static(child) }
        put "</#{tag_str}>"
      end
    end

    def pnode_has_dynamic_attrs?(attrs)
      return false unless attrs&.type == :hash
      attrs.children.any? do |pair|
        next false unless pair.type == :pair
        value = pair.children[1]
        ![:str, :sym, :true, :false].include?(value.type)
      end
    end

    def pnode_has_dynamic_children?(children)
      children.any? do |child|
        if child.type == :pnode_text
          child.children.first.type != :str
        elsif child.type == :pnode
          _, attrs, *grandchildren = child.children
          pnode_has_dynamic_attrs?(attrs) || pnode_has_dynamic_children?(grandchildren)
        else
          true # Any other node type is dynamic
        end
      end
    end

    # Check if children contain loops (recursively)
    def pnode_has_loops?(children)
      children.any? do |child|
        if pnode_is_loop?(child)
          true
        elsif child.type == :pnode
          _, attrs, *grandchildren = child.children
          pnode_has_loops?(grandchildren)
        else
          false
        end
      end
    end

    def output_pnode_attrs_in_template(attrs)
      return unless attrs&.type == :hash

      attrs.children.each do |pair|
        next unless pair.type == :pair

        key_node, value_node = pair.children

        # Get attribute name
        key = case key_node.type
        when :sym then key_node.children.first.to_s
        when :str then key_node.children.first
        else next
        end

        # Convert underscores to dashes (data_foo -> data-foo)
        key = key.gsub('_', '-')

        case value_node.type
        when :str
          put " #{key}=\"#{value_node.children.first.gsub('"', '&quot;')}\""
        when :sym
          put " #{key}=\"#{value_node.children.first}\""
        when :true
          put " #{key}"
        when :false
          # Skip false boolean attributes
        else
          # Dynamic value - use interpolation
          put " #{key}=\"${"
          parse value_node
          put '}"'
        end
      end
    end

    def output_pnode_attrs_static(attrs)
      return unless attrs&.type == :hash

      attrs.children.each do |pair|
        next unless pair.type == :pair

        key_node, value_node = pair.children

        key = case key_node.type
        when :sym then key_node.children.first.to_s
        when :str then key_node.children.first
        else next
        end

        key = key.gsub('_', '-')

        case value_node.type
        when :str
          put " #{key}=\\\"#{value_node.children.first.gsub('"', '&quot;')}\\\""
        when :sym
          put " #{key}=\\\"#{value_node.children.first}\\\""
        when :true
          put " #{key}"
        when :false
          # Skip
        end
      end
    end

    def parse_pnode_attrs_as_object(attrs)
      if attrs.nil? || attrs.type != :hash || attrs.children.empty?
        put '{}'
        return
      end

      put '{'
      first = true
      attrs.children.each do |pair|
        next unless pair.type == :pair

        key_node, value_node = pair.children

        key = case key_node.type
        when :sym then key_node.children.first.to_s
        when :str then key_node.children.first
        else next
        end

        put ', ' unless first
        first = false

        # Output key (quote if needed)
        if key =~ /^[a-zA-Z_$][a-zA-Z0-9_$]*$/
          put key
        else
          put "\"#{key}\""
        end
        put ': '
        parse value_node
      end
      put '}'
    end

    # Check if a pnode child is a loop
    def pnode_is_loop?(child)
      # Check for converted for loops (from functions filter)
      return true if [:for, :for_of, :for_in, :while, :until].include?(child.type)

      # Check for unconverted block loops
      return false unless child.type == :block
      send_node = child.children.first
      return false unless send_node&.type == :send
      method = send_node.children[1]
      # Common loop methods
      [:each, :each_with_index, :map, :select, :reject, :times].include?(method)
    end

    # Output a pnode child when there are loops (uses statements)
    def output_pnode_child_with_loops(child)
      case child.type
      when :pnode_text
        content = child.children.first
        put '_phlex_out += '
        if content.type == :str
          text = content.children.first
          put "`#{text.gsub('`', '\\`').gsub('$', '\\$')}`"
        else
          put 'String('
          parse content
          put ')'
        end
        put '; '
      when :pnode
        put '_phlex_out += '
        tag, attrs, *grandchildren = child.children
        output_pnode_inline_as_expression(tag, attrs, grandchildren)
        put '; '
      when :block, :for, :for_of, :for_in, :while, :until
        # Loop - parse as statement (will generate for loop with _phlex_out +=)
        parse child
        put ' '
      else
        # Other expression
        put '_phlex_out += ('
        parse child
        put '); '
      end
    end

    # Output a pnode as an expression (returns string)
    def output_pnode_inline_as_expression(tag, attrs, children)
      if tag.nil?
        # Fragment - concatenate children
        put '('
        first = true
        children.each do |child|
          put ' + ' unless first
          first = false
          output_pnode_child_as_expression(child)
        end
        put ')'
      else
        tag_str = tag.to_s
        if tag_str[0] =~ /[A-Z]/
          # Component
          put tag_str
          put '.render('
          parse_pnode_attrs_as_object(attrs)
          put ')'
        else
          output_pnode_element(tag_str, attrs, children)
        end
      end
    end

    def output_pnode_child_as_expression(child)
      case child.type
      when :pnode_text
        content = child.children.first
        if content.type == :str
          text = content.children.first
          put "`#{text.gsub('`', '\\`').gsub('$', '\\$')}`"
        else
          put 'String('
          parse content
          put ')'
        end
      when :pnode
        tag, attrs, *grandchildren = child.children
        output_pnode_inline_as_expression(tag, attrs, grandchildren)
      else
        put '('
        parse child
        put ')'
      end
    end
  end
end
