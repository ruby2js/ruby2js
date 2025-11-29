# frozen_string_literal: true

module Ruby2JS
  class PrismWalker
    # Program node (root of the AST)
    def visit_program_node(node)
      visit(node.statements)
    end

    # Statements node (sequence of statements)
    def visit_statements_node(node)
      statements = visit_all(node.body)

      if statements.empty?
        nil
      elsif statements.length == 1
        statements.first
      else
        sl(node, :begin, *statements)
      end
    end

    # Parentheses: (expr)
    def visit_parentheses_node(node)
      if node.body.nil?
        # Empty parentheses: ()
        sl(node, :begin)
      else
        body = visit(node.body)
        if body.nil?
          sl(node, :begin)
        else
          sl(node, :begin, body)
        end
      end
    end

    # Implicit node (for implicit hash values in Ruby 3.1+)
    def visit_implicit_node(node)
      visit(node.value)
    end

    # Missing node (parse error recovery)
    def visit_missing_node(node)
      # This represents a syntax error - return nil
      nil
    end

    # Keyword hash (bare hash in method arguments)
    def visit_keyword_hash_node(node)
      elements = visit_all(node.elements)
      sl(node, :hash, *elements)
    end

    # Arguments node
    def visit_arguments_node(node)
      visit_all(node.arguments)
    end

    # Splat in array: [*a, 1, 2]
    def visit_splat_in_array(node)
      if node.expression
        s(:splat, visit(node.expression))
      else
        s(:splat)
      end
    end

    # Block local variable: |a; b|
    def visit_block_local_variable_node(node)
      s(:shadowarg, node.name)
    end

    # Match required: expr => pattern (Ruby 3.0+)
    def visit_match_required_node(node)
      value = visit(node.value)
      pattern = visit_pattern(node.pattern)
      sl(node, :match_pattern, value, pattern)
    end

    # Match predicate: expr in pattern (Ruby 3.0+)
    def visit_match_predicate_node(node)
      value = visit(node.value)
      pattern = visit_pattern(node.pattern)
      sl(node, :match_pattern_p, value, pattern)
    end

    # Visit a pattern node (produces match_var instead of lvasgn for variables)
    def visit_pattern(node)
      case node
      when Prism::LocalVariableTargetNode
        s(:match_var, node.name)
      when Prism::HashPatternNode
        visit_hash_pattern_node(node)
      when Prism::ArrayPatternNode
        visit_array_pattern_node(node)
      when Prism::PinnedVariableNode
        sl(node, :pin, visit(node.variable))
      when Prism::PinnedExpressionNode
        sl(node, :pin, visit(node.expression))
      else
        # For other node types, use regular visit
        visit(node)
      end
    end

    # Hash pattern: { a:, b: } or { a: x, b: y }
    def visit_hash_pattern_node(node)
      elements = node.elements.map do |assoc|
        if assoc.is_a?(Prism::AssocNode)
          # The value is the pattern
          value = assoc.value
          # Handle ImplicitNode wrapping
          if value.is_a?(Prism::ImplicitNode)
            value = value.value
          end
          visit_pattern(value)
        else
          visit(assoc)
        end
      end
      sl(node, :hash_pattern, *elements)
    end

    # Array pattern: [a, b, *rest]
    def visit_array_pattern_node(node)
      elements = []

      node.requireds.each do |req|
        elements << visit_pattern(req)
      end

      if node.rest
        elements << visit_pattern(node.rest)
      end

      node.posts.each do |post|
        elements << visit_pattern(post)
      end

      sl(node, :array_pattern, *elements)
    end

    # Find pattern: [*, x, *]
    def visit_find_pattern_node(node)
      elements = []

      if node.left
        elements << visit(node.left)
      end

      elements.concat(visit_all(node.requireds))

      if node.right
        elements << visit(node.right)
      end

      sl(node, :find_pattern, *elements)
    end

    # Assoc splat node: **nil in pattern
    def visit_no_keywords_parameter_node(node)
      sl(node, :kwnilarg)
    end

    # Shareable constant (Ractor-related, Ruby 3.0+)
    def visit_shareable_constant_node(node)
      # Just visit the inner write node
      visit(node.write)
    end

    # Call target node (for assignment targets)
    def visit_call_target_node(node)
      receiver = visit(node.receiver)
      type = node.safe_navigation? ? :csend : :send
      sl(node, type, receiver, node.name)
    end

    # Index target node: a[0] as assignment target
    def visit_index_target_node(node)
      receiver = visit(node.receiver)
      args = visit_all(node.arguments&.arguments || [])
      sl(node, :send, receiver, :[], *args)
    end

    # Parameters node
    def visit_parameters_node(node)
      s(:args, *visit_parameters(node))
    end

    # __FILE__ keyword
    def visit_source_file_node(node)
      # Parser gem produces (:str filename) for __FILE__
      # but with our source, we use a special marker that filters can detect
      sl(node, :__FILE__)
    end

    # __LINE__ keyword
    def visit_source_line_node(node)
      sl(node, :int, node.location.start_line)
    end

    # __ENCODING__ keyword
    def visit_source_encoding_node(node)
      # Ruby returns the current file's encoding
      sl(node, :send, s(:const, nil, :Encoding), :default_external)
    end
  end
end
