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
      # Check if destructuring is safe. JavaScript has these constraints:
      # - `let [a, b] = x` works (all new local vars)
      # - `[this.a, this.b] = x` works (all property assignments, no let)
      # - `let a; [a, this.b] = x` works (pre-declared local + property)
      # - `let [a, this.b] = x` FAILS (can't mix let with property in same destructure)
      #
      # We allow destructuring if all targets are the same "kind":
      # - All local variables (lvasgn), OR
      # - All non-local (ivasgn, cvasgn, etc.)
      has_lvasgn = lhs.children.any? { |c| c.type == :lvasgn || c.type == :mlhs || c.type == :splat }
      has_non_lvasgn = lhs.children.any? { |c| [:ivasgn, :cvasgn, :gvasgn, :send].include?(c.type) }

      # If mixed local and non-local, fall through to non-destructuring path
      use_destructuring = es2015 && !(has_lvasgn && has_non_lvasgn)

      if use_destructuring
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
          @vars[var.children.last] ||= (@inner ? :pending : true)
        end

        put '['
        lhs.children.each_with_index do |child, index|
          put ", " unless index == 0
          parse child
        end
        put "] = "
        parse rhs

      elsif rhs.type == :array

        if lhs.children.length == rhs.children.length
          block = []
          # Mark new local vars as :masgn to tell vasgn handler not to treat as setters
          # The marker will be cleared to true when actually processed
          lhs.children.each do |var|
            if var.type == :lvasgn && !@vars.include?(var.children[0])
              @vars[var.children[0]] = :masgn
            end
          end
          lhs.children.zip rhs.children.zip do |var, val|
            block << s(var.type, *var.children, *val)
          end
          parse s(:begin, *block), @state
        else
          raise Error.new("unmatched assignment", @ast)
        end

      else

        block = []
        # Mark new local vars as :masgn to tell vasgn handler not to treat as setters
        lhs.children.each do |var|
          if var.type == :lvasgn && !@vars.include?(var.children[0])
            @vars[var.children[0]] = :masgn
          end
        end
        lhs.children.each_with_index do |var, i|
          block << s(var.type, *var.children, s(:send, rhs, :[], s(:int, i)))
        end
        parse s(:begin, *block), @state
      end
    end
  end
end
