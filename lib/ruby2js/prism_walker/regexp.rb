# frozen_string_literal: true

module Ruby2JS
  class PrismWalker
    # Regular expression: /pattern/flags
    def visit_regular_expression_node(node)
      opts = build_regopt_from_node(node)
      sl(node, :regexp, s(:str, node.unescaped), opts)
    end

    # Interpolated regular expression: /pattern#{var}/flags
    def visit_interpolated_regular_expression_node(node)
      parts = node.parts.map do |part|
        if part.is_a?(Prism::StringNode)
          s(:str, part.unescaped)
        else
          visit(part)
        end
      end

      opts = build_regopt_from_node(node)
      sl(node, :regexp, *parts, opts)
    end

    # Match last line: if /pattern/
    # This is the implicit $_ =~ /pattern/ form
    def visit_match_last_line_node(node)
      opts = build_regopt_from_node(node)
      regexp = s(:regexp, s(:str, node.unescaped), opts)

      sl(node, :match_current_line, regexp)
    end

    # Interpolated match last line
    def visit_interpolated_match_last_line_node(node)
      parts = node.parts.map do |part|
        if part.is_a?(Prism::StringNode)
          s(:str, part.unescaped)
        else
          visit(part)
        end
      end

      opts = build_regopt_from_node(node)
      regexp = s(:regexp, *parts, opts)

      sl(node, :match_current_line, regexp)
    end

    private

    # Build :regopt node from Prism regexp node
    # Uses the predicate methods on the node rather than bit manipulation
    def build_regopt_from_node(node)
      opts = []

      opts << :i if node.ignore_case?
      opts << :m if node.multi_line?
      opts << :x if node.extended?
      opts << :o if node.once?
      opts << :n if node.ascii_8bit?
      opts << :e if node.euc_jp?
      opts << :s if node.windows_31j?
      opts << :u if node.utf_8?

      s(:regopt, *opts)
    end
  end
end
