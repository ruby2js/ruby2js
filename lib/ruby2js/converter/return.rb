module Ruby2JS
  class Converter

    # (return
    #   (int 1))

    handle :return do |value=nil|
      if value
        put 'return '; parse value
      else
        put 'return'
      end
    end

    EXPRESSIONS = [ :array, :float, :hash, :int, :lvar, :nil, :send, :attr,
      :str, :sym, :dstr, :dsym, :cvar, :ivar, :zsuper, :super, :or, :and,
      :block, :const, :true, :false ]

    handle :autoreturn do |*statements|
      return if statements == [nil]
      block = statements.dup
      while block.length == 1 and block.first.type == :begin
        block = block.first.children.dup
      end

      return if block == []
      if EXPRESSIONS.include? block.last.type 
        block.push @ast.updated(:return, [block.pop])
      elsif block.last.type == :if
        node = block.pop
        if node.children[1] and node.children[2] and
          EXPRESSIONS.include? node.children[1].type and
          EXPRESSIONS.include? node.children[2].type
          node = s(:return, node)
        else
          conditions = [[ node.children.first,
            node.children[1] ? s(:autoreturn, node.children[1]) : nil ]]

          while node.children[2] and node.children[2].type == :if
            node = node.children[2]
            conditions.unshift [ node.children.first,
              node.children[1] ? s(:autoreturn, node.children[1]) : nil ]
          end

          node = node.children[2] ? s(:autoreturn, node.children[2]) : nil

          conditions.each do |condition, cstatements| 
            node = s(:if, condition, cstatements, node)
          end
        end
        block.push node
      end

      if block.length == 1
        parse block.first, @state
      else
        parse s(:begin, *block), @state
      end
    end
  end
end
