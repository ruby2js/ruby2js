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

    handle :and, :or do |left, right|
      type = @ast.type


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
      put (type==:and ? ' && ' : ((@or == :nullish and es2020) ? ' ?? ' : ' || '))
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
      else
        group   = LOGICAL.include?( expr.type ) && 
          operator_index( :not ) < operator_index( expr.type )
        group = true if expr and expr.type == :begin

        put '!'; put '(' if group; parse expr; put ')' if group
      end
    end

    # rewrite a && a.b to a&.b
    def rewrite(left, right)
      if left && left.type == :and
        left = rewrite(*left.children)
      end

      if right.type != :send
        s(:and, left, right)
      elsif conditionally_equals(left, right.children.first)
        # a && a.b => a&.b
        right.updated(:csend, [left, right.children.last])
      elsif conditionally_equals(left.children.last, right.children.first)
        # a && b && b.c => a && b&.c
        left.updated(:and, [left.children.first,
          left.children.last.updated(:csend, 
          [left.children.last, right.children.last])])
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
