module Ruby2JS
  class Converter

    # (case
    #   (send nil :a)
    #   (when
    #      (int 1)
    #      (...))
    #   (...))

    handle :case do |expr, *rest|
      whens = rest
      other = whens.pop unless whens.last&.type == :when
      begin
        if @state == :expression
          parse s(:kwbegin, @ast), @state
          return
        end

        inner, @inner = @inner, @ast

        # Hoist local variable declarations from all branches to avoid
        # temporal dead zone issues in JavaScript switch statements.
        # In JS, let/const in one case is hoisted to switch block but
        # uninitialized, causing TDZ errors if another case runs first.
        hoisted = find_case_lvasgns(whens, other)
        unless hoisted.empty?
          put "let #{hoisted.join(', ')}#{@sep}"
          hoisted.each { |name| @vars[name] = true }
        end

        has_range = whens.any? do |node|
          node.children.any? {|child| [:irange, :erange].include? child&.type}
        end

        has_splat = whens.any? do |node|
          node.children.any? {|child| child&.type == :splat}
        end

        # When splat is present, convert to if/else chain instead of switch
        # because JavaScript doesn't support case ...array
        if has_splat
          whens.each_with_index do |node, index|
            *values, code = node.children

            put(index == 0 ? 'if (' : ' else if (')

            values.each_with_index do |value, vi|
              put ' || ' if vi > 0
              if value.type == :splat
                # when *array becomes array.includes(expr)
                parse value.children.first
                put '.includes('
                parse expr
                put ')'
              else
                parse expr
                put ' === '
                parse value
              end
            end

            puts ') {'
            parse code, :statement
            put '}'
          end

          if other
            puts ' else {'
            parse other, :statement
            sput '}'
          end
        elsif has_range
          # https://stackoverflow.com/questions/5619832/switch-on-ranges-of-integers-in-javascript
          puts 'switch (true) {'

          whens.each_with_index do |node, index|
            puts '' unless index == 0

            *values, code = node.children

            values.each do |value|
              put 'case ';
              if value.type == :irange
                parse expr; put ' >= '; parse value.children.first; put " && "
                parse expr; put ' <= '; parse value.children.last; put ":#@ws"
              elsif value.type == :erange
                parse expr; put ' >= '; parse value.children.first; put " && "
                parse expr; put ' < '; parse value.children.last; put ":#@ws"
              else
                parse expr; put ' == '; parse value; put ":#@ws"
              end
            end

            parse code, :statement
            last = code
            while last&.type == :begin
              last = last.children.last
            end

            if other or index < whens.length-1
              put "#{@sep}"
              put "break#@sep" unless last&.type == :return
            end
          end

          (put "#{@nl}default:#@ws"; parse other, :statement) if other

          sput '}'
        else
          if expr
            put 'switch ('; parse expr; puts ') {'
          else
            puts 'switch (true) {'
          end

          whens.each_with_index do |node, index|
            puts '' unless index == 0

            *values, code = node.children

            values.each do |value|
              put 'case ';
              parse value; put ":#@ws"
            end

            parse code, :statement
            last = code
            while last&.type == :begin
              last = last.children.last
            end

            if other or index < whens.length-1
              put "#{@sep}"
              put "break#@sep" unless last&.type == :return
            end
          end

          (put "#{@nl}default:#@ws"; parse other, :statement) if other

          sput '}'
        end
      ensure
        @inner = inner
      end
    end

    # Find all local variable assignments in case branches that would need
    # hoisting. Returns names of variables that are new (not yet in @vars).
    def find_case_lvasgns(whens, other)
      names = []

      whens.each do |w|
        find_lvasgns_in_ast(w.children.last, names)
      end
      find_lvasgns_in_ast(other, names) if other

      # Only return names not already declared
      names.uniq.reject { |name| @vars.key?(name) }
    end

    # Recursively find all lvasgn nodes in an AST, collecting their names
    def find_lvasgns_in_ast(node, names)
      return unless ast_node?(node)

      if node.type == :lvasgn
        names << node.children.first
      end

      # Don't descend into nested scopes that have their own variable scope
      return if [:def, :defs, :class, :module, :sclass, :lambda, :block].include?(node.type)

      node.children.each do |child|
        find_lvasgns_in_ast(child, names)
      end
    end
  end
end
