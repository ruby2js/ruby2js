# frozen_string_literal: true

module Ruby2JS
  class PrismWalker
    # Array literal: [1, 2, 3]
    def visit_array_node(node)
      elements = visit_all(node.elements)
      sl(node, :array, *elements)
    end

    # Hash literal: {a: 1, b: 2}
    def visit_hash_node(node)
      elements = visit_all(node.elements)
      sl(node, :hash, *elements)
    end

    # Key-value pair in hash: a: 1 or :a => 1
    def visit_assoc_node(node)
      key = visit(node.key)

      if node.value.is_a?(Prism::ImplicitNode)
        # Implicit hash value shorthand: {x:} -> {x: x}
        name = node.key.unescaped.to_sym
        value = s(:send, nil, name)
      else
        value = visit(node.value)
      end

      sl(node, :pair, key, value)
    end

    # Double splat in hash: **opts
    def visit_assoc_splat_node(node)
      if node.value
        sl(node, :kwsplat, visit(node.value))
      else
        # Anonymous kwsplat in Ruby 3.2+
        sl(node, :forwarded_kwrestarg)
      end
    end

    # Inclusive range: 1..10
    # Exclusive range: 1...10
    def visit_range_node(node)
      left = visit(node.left)
      right = visit(node.right)
      type = node.exclude_end? ? :erange : :irange
      sl(node, type, left, right)
    end

    # Splat operator: *array
    def visit_splat_node(node)
      if node.expression
        sl(node, :splat, visit(node.expression))
      else
        # Anonymous splat: def foo(*)
        sl(node, :splat)
      end
    end

    # Note: visit_array_pattern_node is defined in misc.rb with proper
    # pattern handling via visit_pattern()

    # %i[] and %I[] symbol arrays (in interpolated form)
    def visit_interpolated_symbol_node(node)
      if node.parts.length == 1 && node.parts.first.is_a?(Prism::StringNode)
        # Simple symbol, no interpolation
        sl(node, :sym, node.parts.first.unescaped.to_sym)
      else
        parts = node.parts.map do |part|
          if part.is_a?(Prism::StringNode)
            s(:str, part.unescaped)
          else
            visit(part)
          end
        end
        sl(node, :dsym, *parts)
      end
    end

    # Note: visit_hash_pattern_node and visit_no_keywords_parameter_node
    # are defined in misc.rb with proper pattern handling
  end
end
