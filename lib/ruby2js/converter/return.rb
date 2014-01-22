module Ruby2JS
  class Converter

    # (return
    #   (int 1))

    handle :return do |value=nil|
      if value
        "return #{ parse value }"
      else
        "return"
      end
    end

    EXPRESSIONS = [ :array, :float, :hash, :int, :lvar, :nil, :send, :attr,
      :str, :sym, :dstr, :dsym ]

    handle :autoreturn do |*statements|
      return if statements == [nil]
      block = statements.dup
      while block.length == 1 and block.first.type == :begin
        block = block.first.children.dup
      end

      if EXPRESSIONS.include? block.last.type 
        block.push s(:return, block.pop)
      end

      if block.length == 1
        parse block.first, @state
      else
        parse s(:begin, *block), @state
      end
    end
  end
end
