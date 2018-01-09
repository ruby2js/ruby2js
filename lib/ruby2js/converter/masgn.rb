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
        walk = lambda do |node|
          results = []
          node.children.each do |var|
            if var.type == :lvasgn
              results << var 
            elsif var.type == :mlhs or var.type == :splat
              results += walk[var]
            end
          end
          results
        end

        vars = walk[lhs]
        newvars = vars.select {|var| not @vars.include? var.children[0]}

        if newvars.length > 0
          if vars == newvars
            put 'let ' 
          else
            put "let #{newvars.map {|var| var.children.last}.join(', ')}#{@sep}"
          end
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
