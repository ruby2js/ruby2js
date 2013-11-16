module Ruby2JS
  class Converter

    # (masgn
    #   (mlhs
    #     (lvasgn :a)
    #     (lvasgn :b))
    #   (array
    #     (int 1)
    #     (int 2)))

    handle :masgn do |lhs, rhs|
      block = []
      lhs.children.zip rhs.children.zip do |var, val| 
        block << s(var.type, *var.children, *val)
      end
      parse s(:begin, *block), @state
    end
  end
end
