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

      lgroup   = LOGICAL.include?( left.type ) && 
        op_index < operator_index( left.type )
      lgroup = true if left and left.type == :begin
      left     = parse left
      left     = "(#{ left })" if lgroup

      if right
        rgroup = LOGICAL.include?( right.type ) && 
          op_index < operator_index( right.type )
        rgroup = true if right.type == :begin
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
