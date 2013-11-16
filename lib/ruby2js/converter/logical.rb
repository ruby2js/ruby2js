module Ruby2JS
  class Converter

    # (and
    #   (...)
    #   (...))

    # (or
    #   (...)
    #   (...))

    # (not
    #   (...))

    handle :and, :or, :not do |left, right=nil|
      type = @ast.type
      op_index = operator_index type

      left = left.children.first if left and left.type == :begin
      lgroup   = LOGICAL.include?( left.type ) && 
        op_index <= operator_index( left.type )
      left     = parse left
      left     = "(#{ left })" if lgroup

      if right
        right = right.children.first if right.type == :begin
        rgroup = LOGICAL.include?( right.type ) && 
          op_index <= operator_index( right.type )
        right    = parse right
        right    = "(#{ right })" if rgroup
      end

      case type
      when :and
        "#{ left } && #{ right }"
      when :or
        "#{ left } || #{ right }"
      else
        "!#{ left }"
      end
    end
  end
end
