# frozen_string_literal: true

module Ruby2JS
  class PrismWalker
    # Interpolated string: "hello #{name}"
    def visit_interpolated_string_node(node)
      parts = node.parts.map do |part|
        if part.is_a?(Prism::StringNode)
          s(:str, part.unescaped)
        elsif part.is_a?(Prism::EmbeddedStatementsNode)
          visit(part)
        else
          visit(part)
        end
      end

      sl(node, :dstr, *parts)
    end

    # Embedded statements in string: #{expr}
    def visit_embedded_statements_node(node)
      if node.statements.nil? || node.statements.body.empty?
        # Empty interpolation: #{}
        s(:begin)
      elsif node.statements.body.length == 1
        visit(node.statements.body.first)
      else
        s(:begin, *visit_all(node.statements.body))
      end
    end

    # Embedded variable in string: "#$global" or "#@ivar"
    def visit_embedded_variable_node(node)
      visit(node.variable)
    end

    # X-string (backticks): `command`
    def visit_x_string_node(node)
      location = XStrLocation.new(
        source: @source,
        start_offset: node.location.start_offset,
        end_offset: node.location.end_offset,
        opening_end: node.opening_loc.end_offset,
        closing_start: node.closing_loc.start_offset
      )
      Node.new(:xstr, [s(:str, node.unescaped)], location: location)
    end

    # Interpolated x-string: `command #{arg}`
    def visit_interpolated_x_string_node(node)
      parts = node.parts.map do |part|
        if part.is_a?(Prism::StringNode)
          s(:str, part.unescaped)
        else
          visit(part)
        end
      end

      location = XStrLocation.new(
        source: @source,
        start_offset: node.location.start_offset,
        end_offset: node.location.end_offset,
        opening_end: node.opening_loc.end_offset,
        closing_start: node.closing_loc.start_offset
      )
      Node.new(:xstr, parts, location: location)
    end

    # Heredoc - handled the same as regular strings
    # The StringNode or InterpolatedStringNode will be created with heredoc content

    # String concatenation: "a" "b" (adjacent string literals)
    # Prism automatically concatenates these, so we just visit the result

    # %w[] word array
    def visit_words_node(node)
      elements = node.elements.map do |element|
        if element.is_a?(Prism::StringNode)
          s(:str, element.unescaped)
        else
          visit(element)
        end
      end
      sl(node, :array, *elements)
    end

    # %W[] interpolated word array
    def visit_interpolated_words_node(node)
      visit_words_node(node)
    end

    # %i[] symbol array
    def visit_symbols_node(node)
      elements = node.elements.map do |element|
        if element.is_a?(Prism::SymbolNode)
          s(:sym, element.unescaped.to_sym)
        else
          visit(element)
        end
      end
      sl(node, :array, *elements)
    end

    # %I[] interpolated symbol array
    def visit_interpolated_symbols_node(node)
      visit_symbols_node(node)
    end
  end
end
