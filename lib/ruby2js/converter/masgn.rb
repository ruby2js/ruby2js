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
        lhs = lhs.children.map {|child| child.children.last}

        if lhs.all? {|var| !@vars.include? var}
          put 'let ' 
        elsif lhs.any? {|var| !@vars.include? var}
          put "let #{lhs.select {|var| !@vars.include? var}.join(', ')}#{@sep}"
        end

        lhs.each {|var| @vars[var] ||= (@scope ? true : :pending)}

        lhs = '[' + lhs.join(', ') + ']'
        put "#{ lhs } = "; parse rhs
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
