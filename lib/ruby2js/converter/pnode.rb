module Ruby2JS
  class Converter

    # pnode (Phlex node) is a synthetic node representing elements in a unified format.
    # Filters consume pnodes and produce target-specific output:
    #   - phlex filter → template literal strings
    #   - react filter → xnode (JSX)
    #
    # Structure: s(:pnode, tag, attrs_hash, *children)
    #   - tag is Symbol (lowercase=HTML, uppercase=Component) or String (custom element) or nil (fragment)
    #   - attrs_hash is s(:hash, ...) with attribute pairs
    #   - children are nested pnodes, pnode_text, or other expressions
    #
    # This handler provides a debug/fallback output if no filter handles the pnode.
    # It outputs a simple representation showing the structure.

    handle :pnode do |tag, attrs, *children|
      # Debug output: show pnode structure
      # In practice, a filter should handle pnodes before they reach here

      if tag.nil?
        # Fragment
        put '/* pnode fragment */'
        children.each_with_index do |child, index|
          put @sep if index > 0
          parse child
        end
      elsif tag.is_a?(Symbol)
        if tag.to_s[0] =~ /[A-Z]/
          # Component
          put "/* pnode Component: #{tag} */"
        else
          # HTML element
          put "/* pnode element: #{tag} */"
        end
        put @nl
        put "<#{tag}"

        # Output attributes
        if attrs && attrs.type == :hash
          attrs.children.each do |pair|
            put ' '
            name = pair.children[0].children[0]
            put name.to_s
            put '='
            value = pair.children[1]
            if value.type == :str
              parse value
            else
              put '{'
              parse value
              put '}'
            end
          end
        end

        if children.empty?
          put '/>'
        else
          put '>'
          children.each { |child| parse child }
          put "</"
          put tag.to_s
          put '>'
        end
      else
        # String = custom element
        put "/* pnode custom: #{tag} */"
        put @nl
        put "<#{tag}"

        if attrs && attrs.type == :hash
          attrs.children.each do |pair|
            put ' '
            name = pair.children[0].children[0]
            put name.to_s
            put '='
            value = pair.children[1]
            if value.type == :str
              parse value
            else
              put '{'
              parse value
              put '}'
            end
          end
        end

        if children.empty?
          put '/>'
        else
          put '>'
          children.each { |child| parse child }
          put "</"
          put tag
          put '>'
        end
      end
    end

    # pnode_text represents text content within a pnode
    # Structure: s(:pnode_text, content_node)
    #   - content_node is s(:str, "text") for static text
    #   - content_node can be any expression for dynamic content

    handle :pnode_text do |content|
      if content.type == :str
        # Static text - output directly
        put content.children.first
      else
        # Dynamic content - wrap in braces (JSX-style for debug output)
        put '{'
        parse content
        put '}'
      end
    end
  end
end
