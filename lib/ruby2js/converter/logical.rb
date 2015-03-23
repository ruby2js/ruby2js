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
      op_index = operator_index type

      lgroup   = LOGICAL.include?( left.type ) && 
        op_index < operator_index( left.type )
      lgroup = true if left and left.type == :begin

      rgroup = LOGICAL.include?( right.type ) && 
        op_index < operator_index( right.type )
      rgroup = true if right.type == :begin

      put '(' if lgroup; parse left; put ')' if lgroup
      put (type==:and ? ' && ' : ' || ')
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
  end
end
