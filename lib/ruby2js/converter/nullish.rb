module Ruby2JS
  class Converter

    # (nullish_or
    #   (...)
    #   (...))
    #
    # Synthetic node type for nullish coalescing operator (??)
    # Created by pragma filter when # Pragma: ?? is used

    handle :nullish_or do |left, right|
      op_index = operator_index :or

      lgroup = LOGICAL.include?(left.type) &&
        op_index < operator_index(left.type)
      lgroup = true if left && left.type == :begin

      rgroup = LOGICAL.include?(right.type) &&
        op_index < operator_index(right.type)
      rgroup = true if right.type == :begin

      put '(' if lgroup; parse left; put ')' if lgroup
      put ' ?? '
      put '(' if rgroup; parse right; put ')' if rgroup
    end

    # (nullish_asgn
    #   (lvasgn :a)
    #   (...))
    #
    # Synthetic node type for nullish assignment operator (??=)
    # Created by pragma filter when # Pragma: ?? is used on ||=

    handle :nullish_asgn do |asgn, value|
      vtype = nil
      vtype = :lvar if asgn.type == :lvasgn
      vtype = :ivar if asgn.type == :ivasgn
      vtype = :cvar if asgn.type == :cvasgn

      if es2021
        # Use ??= operator directly
        parse s(:op_asgn, asgn, '??', value)
      elsif vtype
        # Fallback: expand to a = a ?? b
        parse s(asgn.type, asgn.children.first, s(:nullish_or,
          s(vtype, asgn.children.first), value))
      elsif asgn.type == :send && asgn.children[1] == :[]
        parse s(:send, asgn.children.first, :[]=,
          asgn.children[2], s(:nullish_or, asgn, value))
      else
        parse s(:send, asgn.children.first, "#{asgn.children[1]}=",
          s(:nullish_or, asgn, value))
      end
    end
  end
end
