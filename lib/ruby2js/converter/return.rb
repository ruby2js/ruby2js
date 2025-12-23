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

    EXPRESSIONS = [ :array, :float, :hash, :int, :lvar, :nil, :send, :send!, :attr,
      :str, :sym, :dstr, :dsym, :cvar, :ivar, :zsuper, :super, :or, :and,
      :block, :const, :true, :false, :xnode, :taglit, :self,
      :op_asgn, :and_asgn, :or_asgn, :taglit, :gvar, :csend, :call, :typeof ]

    handle :autoreturn do |*statements|
      return if statements.length == 1 && statements.first.nil?
      block = statements.dup # Pragma: array
      while block.length == 1 && block.first && block.first.type == :begin
        block = block.first.children.dup # Pragma: array
      end

      return if block.empty?
      return unless block.last

      # Don't add return to << sends - they convert to .push() only in statement context
      # Adding return would put them in expression context where << outputs as invalid JS
      is_push_send = block.last.type == :send && block.last.children[1] == :<<

      if EXPRESSIONS.include?(block.last.type) && !is_push_send
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

      elsif block.last.type == :case
        node = block.pop
        children = node.children.dup # Pragma: array
        (1...children.length).each do |i|
          next if children[i].nil? # case statements without else clause end with nil

          if children[i].type == :when
            gchildren = children[i].children.dup # Pragma: array
            if !gchildren.empty? and EXPRESSIONS.include? gchildren.last.type
              gchildren.push s(:return, gchildren.pop)
              children[i] = children[i].updated(nil, gchildren)
            elsif !gchildren.empty? and gchildren.last.type == :begin
              # Multi-statement when body - apply autoreturn to the begin block
              gchildren[-1] = s(:autoreturn, gchildren.last)
              children[i] = children[i].updated(nil, gchildren)
            end
          elsif EXPRESSIONS.include? children[i].type
            children[i] = children[i].updated(:return, [children[i]])
          end
        end
        block.push node.updated(nil, children)

      elsif block.last.type == :lvasgn
        block.push s(:return, s(:lvar, block.last.children.first))
      elsif block.last.type == :ivasgn
        block.push s(:return, s(:ivar, block.last.children.first))
      elsif block.last.type == :cvasgn
        block.push s(:return, s(:cvar, block.last.children.first))

      elsif block.last.type == :kwbegin
        # Unwrap kwbegin and process its contents for autoreturn
        kwbegin = block.pop
        inner = kwbegin.children.first
        if inner&.type == :ensure
          # For ensure blocks, apply autoreturn to the try body only
          try_body = inner.children.first
          ensure_body = inner.children.last
          block.push kwbegin.updated(nil, [
            inner.updated(nil, [s(:autoreturn, try_body), ensure_body])
          ])
        else
          block.push kwbegin.updated(nil, [s(:autoreturn, *kwbegin.children)])
        end

      elsif block.last.type == :ensure
        # For ensure blocks, apply autoreturn to the try body only
        node = block.pop
        try_body = node.children.first
        ensure_body = node.children.last
        block.push node.updated(nil, [s(:autoreturn, try_body), ensure_body])
      end

      if block.length == 1
        parse block.first, @state
      else
        parse s(:begin, *block), @state
      end
    end
  end
end
