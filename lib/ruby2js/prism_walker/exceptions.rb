# frozen_string_literal: true

module Ruby2JS
  class PrismWalker
    # Begin block: begin; x; rescue; y; ensure; z; end
    def visit_begin_node(node)
      # A begin node might contain:
      # - statements (the main body)
      # - rescue_clause (one or more rescue handlers)
      # - else_clause
      # - ensure_clause

      if node.rescue_clause || node.ensure_clause
        body = visit(node.statements)

        if node.rescue_clause
          # Build rescue handlers chain
          handlers = []
          current = node.rescue_clause
          while current
            handlers << visit_resbody(current)
            current = current.subsequent
          end

          else_body = node.else_clause ? visit(node.else_clause.statements) : nil
          rescue_node = s(:rescue, body, *handlers, else_body)

          if node.ensure_clause
            ensure_body = visit(node.ensure_clause.statements)
            sl(node, :kwbegin, s(:ensure, rescue_node, ensure_body))
          else
            sl(node, :kwbegin, rescue_node)
          end
        else
          # Just ensure, no rescue
          ensure_body = visit(node.ensure_clause.statements)
          sl(node, :kwbegin, s(:ensure, body, ensure_body))
        end
      else
        # Just a begin block with no rescue/ensure
        # This is used for grouping
        body = visit(node.statements)
        if body
          sl(node, :kwbegin, body)
        else
          sl(node, :kwbegin)
        end
      end
    end

    # Individual rescue handler (RescueNode in Prism)
    def visit_resbody(node)
      # Exception types - Parser gem always wraps in an array
      exceptions = if node.exceptions && !node.exceptions.empty?
        types = visit_all(node.exceptions)
        s(:array, *types)
      else
        nil
      end

      # Exception variable - this is a LocalVariableTargetNode, not an assignment
      exception_var = if node.reference
        # For rescue => e, the reference is a target node
        # Parser expects s(:lvasgn, :e) for this
        if node.reference.is_a?(Prism::LocalVariableTargetNode)
          s(:lvasgn, node.reference.name)
        else
          visit(node.reference)
        end
      else
        nil
      end

      # Handler body
      body = visit(node.statements)

      s(:resbody, exceptions, exception_var, body)
    end

    # Rescue modifier: expr rescue fallback
    def visit_rescue_modifier_node(node)
      expression = visit(node.expression)
      rescue_expr = visit(node.rescue_expression)

      sl(node, :rescue,
        expression,
        s(:resbody, nil, nil, rescue_expr),
        nil)
    end

    # Ensure clause - usually visited as part of visit_begin_node
    def visit_ensure_node(node)
      visit(node.statements)
    end

    # RescueNode is visited indirectly via visit_resbody, but we need this
    # for cases where Prism visits it directly
    def visit_rescue_node(node)
      visit_resbody(node)
    end
  end
end
