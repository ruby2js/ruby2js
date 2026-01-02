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
          lgroup = Converter::LOGICAL.include?(left.type) && op_index < operator_index(left.type)
          lgroup = true if left and left.type == :begin
          rgroup = Converter::LOGICAL.include?(right.type) && op_index < operator_index(right.type)
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
        if type == :or
          @need_truthy_helpers << :ror
          put '$ror('
          parse left
          put ", () => "
          parse right
          put ")"
        else
          @need_truthy_helpers << :rand
          put '$rand('
          parse left
          put ", () => "
          parse right
          put ")"
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

      lgroup   = Converter::LOGICAL.include?( left.type ) &&
        op_index < operator_index( left.type )
      lgroup = true if left and left.type == :begin

      rgroup = Converter::LOGICAL.include?( right.type ) &&
        op_index < operator_index( right.type )
      rgroup = true if right.type == :begin
      # Assignment on RHS needs parentheses in JS: a && b = c -> a && (b = c)
      rgroup = true if %i[lvasgn ivasgn cvasgn gvasgn masgn].include?(right.type)

      # Determine whether to use ?? or ||
      # :auto (default) - context-aware: || in boolean contexts, ?? in value contexts
      # :nullish - always use ??
      # :logical - always use ||
      # Note: Chained || operators (e.g., a || b || c) always use || consistently
      # to avoid JavaScript syntax errors from mixing ?? and || operators.
      use_nullish = case @or
        when :logical then false
        when :nullish then !boolean_expression?(left) && !boolean_expression?(right)
        else # :auto - context-aware
          # For chained || (left is an :or node), use || consistently
          !@boolean_context && !boolean_expression?(left) && !boolean_expression?(right) &&
            left.type != :or
        end

      # If we're using || and left is an :or node, force || for the entire chain
      # to avoid mixing ?? and || (which is a JavaScript syntax error)
      if type == :or && !use_nullish && left.type == :or
        saved_or, @or = @or, :logical
        put '(' if lgroup; parse left; put ')' if lgroup
        @or = saved_or
      else
        put '(' if lgroup; parse left; put ')' if lgroup
      end

      put (type==:and ? ' && ' : (use_nullish ? ' ?? ' : ' || '))

      # Same for right child - force || if we're using || and right contains :or
      # This handles cases like: a ||= b || c where we expand to a = a || (b || c)
      if type == :or && !use_nullish && right.type == :or
        saved_or, @or = @or, :logical
        put '(' if rgroup; parse right; put ')' if rgroup
        @or = saved_or
      else
        put '(' if rgroup; parse right; put ')' if rgroup
      end
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
      # Handle nil left (e.g., from nullish_to_s on nil.to_s)
      if left.nil?
        put 'null ?? '
        parse right
        return
      end

      # Only group :begin if it has multiple children (actual grouping expression)
      # Single-child :begin nodes are just wrappers and don't need parens
      lgroup = Converter::LOGICAL.include?(left.type) ||
        (left.type == :begin && left.children.length > 1)
      rgroup = right && (Converter::LOGICAL.include?(right.type) ||
        (right.type == :begin && right.children.length > 1))

      put '(' if lgroup; parse left; put ')' if lgroup
      put ' ?? '
      put '(' if rgroup; parse right; put ')' if rgroup
    end

    # (not
    #   (...))

    handle :not do |expr|

      if expr.type == :send and Converter::INVERT_OP[expr.children[1]]
        parse(s(:send, expr.children[0], Converter::INVERT_OP[expr.children[1]],
          expr.children[2]))
      elsif expr.type == :send and expr.children[1] == :!
        # Double negation: not(!inner)
        inner = expr.children[0]
        # Unwrap :begin nodes (from parentheses)
        inner = inner.children.first if inner&.type == :begin && inner.children.length == 1
        if inner&.type == :send and Converter::INVERT_OP[inner.children[1]]
          # not(!(comparison)) → comparison (double negation cancels)
          parse inner
        elsif inner&.type == :send and inner.children[1] == :!
          # Triple+ negation: not(!(!x)) → not(x)
          # Recursively handle by parsing the inner negation as :not
          parse s(:not, inner.children[0])
        else
          # Preserve !!x for boolean coercion
          group = Converter::LOGICAL.include?(expr.type) &&
            operator_index(:not) < operator_index(expr.type)
          group = true if expr and %i[begin in?].include? expr.type
          put '!'; put '(' if group; parse expr; put ')' if group
        end
      elsif expr.type == :defined?
        parse s(:undefined?, *expr.children)
      elsif expr.type == :or
        parse s(:and, s(:not, expr.children[0]), s(:not, expr.children[1]))
      elsif expr.type == :and
        parse s(:or, s(:not, expr.children[0]), s(:not, expr.children[1]))
      elsif expr.type == :send and expr.children[0] == nil and
        expr.children[1] == :typeof and expr.children[2]&.type == :send and
        Converter::INVERT_OP[expr.children[2].children[1]]
        # Handle "not typeof x == y" => "typeof x != y"
        # Ruby parses "typeof x == y" as "typeof(x == y)" due to precedence
        cmp = expr.children[2]
        parse(s(:send, s(:send, nil, :typeof, cmp.children[0]),
          Converter::INVERT_OP[cmp.children[1]], cmp.children[2]))
      else
        group   = Converter::LOGICAL.include?( expr.type ) &&
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

      if right.type != :send or Converter::OPERATORS.flatten.include? right.children[1]
        s(:and, left, right)
      elsif conditionally_equals(left, right.children.first)
        # a && a.b => a&.b
        right.updated(:csend, [left, *right.children[1..-1]])
      elsif left.type != :in? && conditionally_equals(left.children.last, right.children.first)
        # a && b && b.c => a && b&.c
        # Skip for :in? nodes - their structure is (in? prop target) not (and left right)
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
      # Use .equals for deep comparison (works in both Ruby and JavaScript)
      if left.respond_to?(:equals) && left.equals(right)
        true
      elsif left == right
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
