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
      use_destructuring = !(has_lvasgn && has_non_lvasgn)

      # Check for middle-splat: *a, b = arr - JS doesn't allow [...a, b]
      # Need to handle this specially: b = arr.pop(); a = arr.slice() or similar
      # Note: Using >= 0 check for JS compatibility (findIndex returns -1, not nil)
      splat_index = lhs.children.find_index { |c| c.type == :splat }
      has_middle_splat = splat_index && splat_index >= 0 && splat_index < lhs.children.length - 1

      if has_middle_splat && use_destructuring
        # Transform: *a, b, c = arr
        # Into: let $temp = arr.slice(); let c = $temp.pop(); let b = $temp.pop(); let a = $temp;
        before_splat = lhs.children[0...splat_index]
        splat_var = lhs.children[splat_index].children.first
        after_splat = lhs.children[(splat_index + 1)..]

        # Get the variable name from the splat
        splat_name = splat_var.type == :lvasgn ? splat_var.children.first : nil

        # Generate temp variable and slice
        temp_var = :$masgn_temp
        block = []

        # Mark all vars as :masgn so they get let declarations
        before_splat.each do |var|
          var_name = var.children.first
          @vars[var_name] = :masgn unless @vars.include?(var_name)
        end
        after_splat.each do |var|
          var_name = var.children.first
          @vars[var_name] = :masgn unless @vars.include?(var_name)
        end
        if splat_name
          @vars[splat_name] = :masgn unless @vars.include?(splat_name)
        end

        # First assign rhs to temp (sliced if it's an array/call)
        actual_rhs = rhs.type == :splat ? rhs.children.first : rhs
        block << s(:lvasgn, temp_var, s(:send!, actual_rhs, :slice))

        # Assign any vars before the splat from the front
        before_splat.each do |var|
          var_name = var.children.first
          block << s(:lvasgn, var_name, s(:send, s(:lvar, temp_var), :shift))
        end

        # Pop vars after the splat from the end (in reverse order)
        after_splat.reverse.each do |var|
          var_name = var.children.first
          block << s(:lvasgn, var_name, s(:send, s(:lvar, temp_var), :pop))
        end

        # Assign remaining temp to the splat variable
        if splat_name
          block << s(:lvasgn, splat_name, s(:lvar, temp_var))
        end

        parse s(:begin, *block), @state
      elsif use_destructuring
        # Note: Using .call instead of [] for selfhost JS compatibility
        walk = lambda do |node|
          results = []
          node.children.each do |var|
            if var.type == :lvasgn
              results << var
            elsif var.type == :mlhs or var.type == :splat
              results += walk.call(var)
            end
          end
          results
        end

        vars = walk.call(lhs)
        newvars = vars.select {|var| not @vars.include? var.children[0]}

        if newvars.length > 0
          # Note: Using length comparison for JS compatibility (== compares references in JS)
          if vars.length == newvars.length
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
        # When rhs is a splat on an array variable, unwrap it
        # Ruby: a, b = *arr → JS: [a, b] = arr (not ...arr)
        if rhs.type == :splat
          parse rhs.children.first
        else
          parse rhs
        end

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
