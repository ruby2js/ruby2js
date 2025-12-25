# frozen_string_literal: true

module Ruby2JS
  class PrismWalker
    # Integer literals: 1, 0xFF, 0b1010, etc.
    def visit_integer_node(node)
      sl(node, :int, node.value)
    end

    # Float literals: 1.0, 1e10, etc.
    def visit_float_node(node)
      sl(node, :float, node.value)
    end

    # Rational literals: 1r, 2.5r
    def visit_rational_node(node)
      sl(node, :rational, node.value)
    end

    # Imaginary/Complex literals: 1i, 2+3i
    def visit_imaginary_node(node)
      sl(node, :complex, node.value)
    end

    # String literals: 'string', "string", heredocs
    def visit_string_node(node)
      # Check if this is a heredoc by examining the opening delimiter
      opening = @source[node.opening_loc.start_offset, node.opening_loc.length] if node.opening_loc
      is_heredoc = opening&.start_with?('<<')

      # Check if string actually spans multiple lines in source (not just contains \n escape)
      # Uses node_multiline? helper which works in both Ruby and JavaScript
      is_multiline = node_multiline?(node)

      if is_heredoc && node.unescaped.empty?
        # Empty heredocs should be dstr (dynamic string) with no children
        # This matches Parser gem behavior and ensures proper newline handling
        sl(node, :dstr)
      elsif is_multiline && node.unescaped.include?("\n")
        # Actual multi-line strings should be dstr with str children split on newlines
        # This matches Parser gem behavior for template literal detection
        parts = node.unescaped.split(/(\n)/).reject(&:empty?)
        children = []
        parts.each_with_index do |part, i|
          if part == "\n"
            # Append newline to previous part if exists, otherwise create new part
            if children[-1]
              children[-1] = s(:str, children[-1].children[0] + "\n")
            else
              children << s(:str, "\n")
            end
          else
            children << s(:str, part)
          end
        end
        # Handle trailing newline
        if node.unescaped.end_with?("\n") && children[-1] && !children[-1].children[0].end_with?("\n")
          children[-1] = s(:str, children[-1].children[0] + "\n")
        end
        sl(node, :dstr, *children)
      else
        sl(node, :str, node.unescaped)
      end
    end

    # Symbol literals: :symbol
    def visit_symbol_node(node)
      sl(node, :sym, node.unescaped.to_sym)
    end

    # nil
    def visit_nil_node(node)
      sl(node, :nil)
    end

    # true
    def visit_true_node(node)
      sl(node, :true)
    end

    # false
    def visit_false_node(node)
      sl(node, :false)
    end

    # self
    def visit_self_node(node)
      sl(node, :self)
    end

    # Note: __FILE__, __LINE__, __ENCODING__ are defined in misc.rb
  end
end
