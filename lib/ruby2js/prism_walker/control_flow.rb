# frozen_string_literal: true

module Ruby2JS
  class PrismWalker
    # If statement: if x; y; else; z; end
    def visit_if_node(node)
      condition = visit(node.predicate)
      then_body = visit(node.statements)
      # Ruby 3.3 uses .consequent, Ruby 3.4+ uses .subsequent
      else_clause = node.respond_to?(:subsequent) ? node.subsequent : node.consequent
      else_body = visit(else_clause)

      sl(node, :if, condition, then_body, else_body)
    end

    # Unless statement: unless x; y; else; z; end
    def visit_unless_node(node)
      condition = visit(node.predicate)
      then_body = visit(node.statements)
      else_body = visit(node.else_clause) ? visit(node.else_clause.statements) : nil

      # Parser gem represents unless as: if(condition, else_body, then_body)
      sl(node, :if, condition, else_body, then_body)
    end

    # Case statement: case x; when 1; a; when 2; b; else; c; end
    def visit_case_node(node)
      predicate = visit(node.predicate)
      conditions = visit_all(node.conditions)
      else_body = node.else_clause ? visit(node.else_clause.statements) : nil

      sl(node, :case, predicate, *conditions, else_body)
    end

    # When clause: when 1, 2; x
    def visit_when_node(node)
      conditions = visit_all(node.conditions)
      body = visit(node.statements)

      sl(node, :when, *conditions, body)
    end

    # Case-in (pattern matching) - not fully supported by Ruby2JS
    def visit_case_match_node(node)
      predicate = visit(node.predicate)
      conditions = visit_all(node.conditions)
      else_body = node.else_clause ? visit(node.else_clause.statements) : nil

      sl(node, :case_match, predicate, *conditions, else_body)
    end

    # In clause for pattern matching
    def visit_in_node(node)
      pattern = visit(node.pattern)
      body = visit(node.statements)

      sl(node, :in_pattern, pattern, nil, body)
    end

    # While loop: while x; y; end
    def visit_while_node(node)
      condition = visit(node.predicate)
      body = visit(node.statements)

      # Check for begin..end while (post-condition loop)
      if node.begin_modifier?
        sl(node, :while_post, condition, body)
      else
        sl(node, :while, condition, body)
      end
    end

    # Until loop: until x; y; end
    def visit_until_node(node)
      condition = visit(node.predicate)
      body = visit(node.statements)

      # Check for begin..end until (post-condition loop)
      if node.begin_modifier?
        sl(node, :until_post, condition, body)
      else
        sl(node, :until, condition, body)
      end
    end

    # For loop: for x in y; z; end
    def visit_for_node(node)
      var = visit(node.index)
      collection = visit(node.collection)
      body = visit(node.statements)

      sl(node, :for, var, collection, body)
    end

    # Break: break or break value
    def visit_break_node(node)
      if node.arguments
        args = visit_all(node.arguments.arguments)
        sl(node, :break, *args)
      else
        sl(node, :break)
      end
    end

    # Next: next or next value
    def visit_next_node(node)
      if node.arguments
        args = visit_all(node.arguments.arguments)
        sl(node, :next, *args)
      else
        sl(node, :next)
      end
    end

    # Return: return or return value
    def visit_return_node(node)
      if node.arguments
        args = visit_all(node.arguments.arguments)
        if args.length == 1
          sl(node, :return, args.first)
        else
          sl(node, :return, s(:array, *args))
        end
      else
        sl(node, :return)
      end
    end

    # Redo
    def visit_redo_node(node)
      sl(node, :redo)
    end

    # Retry
    def visit_retry_node(node)
      sl(node, :retry)
    end

    # Else clause (for case/if)
    def visit_else_node(node)
      visit(node.statements)
    end

    # Note: visit_match_predicate_node and visit_match_required_node
    # are defined in misc.rb with proper pattern handling via visit_pattern()

    # Match write node: /(?<name>...)/ =~ str
    def visit_match_write_node(node)
      visit(node.call)
    end

    # Capture pattern: expr => var
    def visit_capture_pattern_node(node)
      value = visit(node.value)
      target = visit(node.target)
      sl(node, :match_as, value, target)
    end

    # Alternation pattern: a | b
    def visit_alternation_pattern_node(node)
      left = visit(node.left)
      right = visit(node.right)
      sl(node, :match_alt, left, right)
    end

    # Local variable target in pattern matching
    def visit_local_variable_target_in_pattern(node)
      sl(node, :match_var, node.name)
    end

    # Pinned variable: ^foo
    def visit_pinned_variable_node(node)
      sl(node, :pin, visit(node.variable))
    end

    # Pinned expression: ^(expr)
    def visit_pinned_expression_node(node)
      sl(node, :pin, visit(node.expression))
    end
  end
end
