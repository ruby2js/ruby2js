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
      if es2015
        newvars = lhs.children.select do |var|
          var.type == :lvasgn and not @vars.include? var.children.last
        end

        if newvars.length == lhs.children.length
          put 'let ' 
        elsif newvars.length > 0
          put "let #{newvars.map {|var| var.children.last}.join(', ')}#{@sep}"
        end

        newvars.each do |var| 
          @vars[var.children.last] ||= (@scope ? true : :pending)
        end

        put '['
        lhs.children.each_with_index do |child, index|
          put ", " unless index == 0
          parse child
        end
        put "] = "
        parse rhs
      else
        block = []
        lhs.children.zip rhs.children.zip do |var, val| 
          block << s(var.type, *var.children, *val)
        end
        parse s(:begin, *block), @state
      end
    end
  end
end
