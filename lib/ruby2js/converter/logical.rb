module Ruby2JS
  class Converter

    # (and
    #   (...)
    #   (...))

    # (or
    #   (...)
    #   (...))

    # Note: not handled below
    #   (...))

    # Comparison operators that indicate a boolean context
    COMPARISON_OPS = [:<, :<=, :>, :>=, :==, :!=, :===, :'!==', :=~, :!~]

    # Check if a node represents a boolean expression (comparison, boolean literal, etc.)
    def boolean_expression?(node)
      return false unless node

      case node.type
      when :true, :false
        true
      when :send
        # Check for comparison operators
        method = node.children[1]
        return true if COMPARISON_OPS.include?(method)
        # Check for predicate methods (ending with ?)
        return true if method.to_s.end_with?('?')
        # Check for negation (Ruby parses !x as x.!)
        return true if method == :!
        false
      when :and, :or, :not
        true
      when :begin
        # Check the inner expression
        node.children.length == 1 && boolean_expression?(node.children.first)
      else
        false
      end
    end

    handle :and, :or do |left, right|
      type = @ast.type

      # Use Ruby-style truthiness when truthy: :ruby option is enabled
      if @truthy == :ruby
        # In boolean context, we can optimize: use $T(a) || $T(b) instead of $ror/$rand
        # This preserves short-circuit evaluation and is simpler than the helper functions
        if @boolean_context
          @need_truthy_helpers << :T
          op_index = operator_index type
          lgroup = LOGICAL.include?(left.type) && op_index < operator_index(left.type)
          lgroup = true if left and left.type == :begin
          rgroup = LOGICAL.include?(right.type) && op_index < operator_index(right.type)
          rgroup = true if right.type == :begin

          # Check if child is an and/or (possibly wrapped in begin node)
          # If so, don't wrap with $T since it will output $T itself
          left_inner = left.type == :begin && left.children.length == 1 ? left.children.first : left
          right_inner = right.type == :begin && right.children.length == 1 ? right.children.first : right

          if [:and, :or].include?(left_inner.type)
            put '(' if lgroup; parse left; put ')' if lgroup
          else
            put '$T('; put '(' if lgroup; parse left; put ')' if lgroup; put ')'
          end
          put(type == :and ? ' && ' : ' || ')
          if [:and, :or].include?(right_inner.type)
            put '(' if rgroup; parse right; put ')' if rgroup
          else
            put '$T('; put '(' if rgroup; parse right; put ')' if rgroup; put ')'
          end
          return
        end

        @need_truthy_helpers << :T
        thunk_start = es2015 ? '() => ' : 'function() {return '
        thunk_end = es2015 ? '' : '}'
        if type == :or
          @need_truthy_helpers << :ror
          put '$ror('
          parse left
          put ", #{thunk_start}"
          parse right
          put "#{thunk_end})"
        else
          @need_truthy_helpers << :rand
          put '$rand('
          parse left
          put ", #{thunk_start}"
          parse right
          put "#{thunk_end})"
        end
        return
      end

      if es2020 and type == :and
        node = rewrite(left, right)
        if node.type == :csend
          return parse right.updated(node.type, node.children)
        else
          left, right = node.children
        end
      end

      op_index = operator_index type

      lgroup   = LOGICAL.include?( left.type ) &&
        op_index < operator_index( left.type )
      lgroup = true if left and left.type == :begin

      rgroup = LOGICAL.include?( right.type ) &&
        op_index < operator_index( right.type )
      rgroup = true if right.type == :begin

      put '(' if lgroup; parse left; put ')' if lgroup

      # Use || instead of ?? in boolean contexts even when nullish option is set
      use_nullish = @or == :nullish && es2020 &&
        !boolean_expression?(left) && !boolean_expression?(right)

      put (type==:and ? ' && ' : (use_nullish ? ' ?? ' : ' || '))
      put '(' if rgroup; parse right; put ')' if rgroup
    end

    # (nullish
    #   (...)
    #   (...))
    #
    # Explicit nullish coalescing (??) - used by nullish_to_s option
    # to wrap expressions that need nil-safe string coercion.
    # Unlike :or with @or == :nullish, this always emits ?? regardless of
    # the global @or setting.

    handle :nullish do |left, right|
      # Only group :begin if it has multiple children (actual grouping expression)
      # Single-child :begin nodes are just wrappers and don't need parens
      lgroup = LOGICAL.include?(left.type) ||
        (left.type == :begin && left.children.length > 1)
      rgroup = LOGICAL.include?(right.type) ||
        (right.type == :begin && right.children.length > 1)

      put '(' if lgroup; parse left; put ')' if lgroup
      put ' ?? '
      put '(' if rgroup; parse right; put ')' if rgroup
    end

    # (not
    #   (...))

    handle :not do |expr|

      if expr.type == :send and INVERT_OP.include? expr.children[1]
        parse(s(:send, expr.children[0], INVERT_OP[expr.children[1]],
          expr.children[2]))
      elsif expr.type == :defined?
        parse s(:undefined?, *expr.children)
      elsif expr.type == :or
        parse s(:and, s(:not, expr.children[0]), s(:not, expr.children[1]))
      elsif expr.type == :and
        parse s(:or, s(:not, expr.children[0]), s(:not, expr.children[1]))
      elsif expr.type == :send and expr.children[0..1] == [nil, :typeof] and
        expr.children[2]&.type == :send and
        INVERT_OP.include?(expr.children[2].children[1])
        # Handle "not typeof x == y" => "typeof x != y"
        # Ruby parses "typeof x == y" as "typeof(x == y)" due to precedence
        comparison = expr.children[2]
        parse(s(:send, s(:send, nil, :typeof, comparison.children[0]),
          INVERT_OP[comparison.children[1]], comparison.children[2]))
      else
        group   = LOGICAL.include?( expr.type ) &&
          operator_index( :not ) < operator_index( expr.type )
        group = true if expr and %i[begin in?].include? expr.type

        put '!'; put '(' if group; parse expr; put ')' if group
      end
    end

    # rewrite a && a.b to a&.b
    def rewrite(left, right)
      if left && left.type == :and
        left = rewrite(*left.children)
      end

      if right.type != :send or OPERATORS.flatten.include? right.children[1]
        s(:and, left, right)
      elsif conditionally_equals(left, right.children.first)
        # a && a.b => a&.b
        right.updated(:csend, [left, *right.children[1..-1]])
      elsif conditionally_equals(left.children.last, right.children.first)
        # a && b && b.c => a && b&.c
        left.updated(:and, [left.children.first,
          left.children.last.updated(:csend, 
          [left.children.last, *right.children[1..-1]])])
      else
        s(:and, left, right)
      end
    end

    # determine if two trees are identical, modulo conditionalilties
    # in other words a.b == a&.b
    def conditionally_equals(left, right)
      if left == right
        true
      elsif !left.respond_to?(:type) or !left or !right or left.type != :csend or right.type != :send
        false
      else
        conditionally_equals(left.children.first, right.children.first) &&
          conditionally_equals(left.children.last, right.children.last)
      end
    end
  end
end
