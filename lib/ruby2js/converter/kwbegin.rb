module Ruby2JS
  class Converter

    # (rescue
    #   (send nil :a)
    #     (resbody nil nil
    #       (send nil :b)) nil)
    handle :rescue do |*statements|
      parse s(:kwbegin, s(:rescue, *statements)), @state
    end

    # (kwbegin
    #   (ensure
    #     (rescue
    #       (send nil :a)
    #       (resbody nil nil
    #         (send nil :b)) nil)
    #    (send nil :c)))

    handle :kwbegin do |*children|
      block = children.first

      if @state == :expression
        parse s(:send, s(:block, s(:send, nil, :proc), s(:args),
          s(:begin, s(:autoreturn, *children))), :[])
        return
      end

      # Declare variables at function scope for JS compatibility
      # (Ruby allows creating vars inside if blocks; JS needs them declared first)
      body = nil
      recovers = nil
      otherwise = nil
      finally = nil
      uses_retry = false

      if block&.type == :ensure
        block, finally = block.children
      end

      if block and block.type == :rescue
        body, *recovers, otherwise = block.children

        # Collect all unique exception variables used across rescue clauses
        exception_vars = []
        recovers.each do |r|
          v = r.children[1]
          exception_vars << v if v and not exception_vars.include?(v)
        end

        # Use a common catch variable - prefer the first named one, or $EXCEPTION
        var = exception_vars.first

        if recovers[0..-2].any? {|recover| not recover.children[0]}
          raise Error.new(
            "additional recovers after catchall", @ast)
        end

        # Check if any rescue body contains a retry statement
        has_retry = nil
        has_retry = ->(node) {
          return false unless ast_node?(node)
          return true if node.type == :retry
          node.children.any? { |child| has_retry.call(child) } # Pragma: method
        }
        uses_retry = recovers.any? { |recover| has_retry.call(recover.children.last) } # Pragma: method
      else
        body = block
      end

      if not recovers and not finally
        # Wrap in a JavaScript block to create scope
        puts '{'
        scope s(:begin, *children)
        sput '}'
        return
      end

      # Find variables declared in try that are used in finally
      # These need to be hoisted before the try block
      # We wrap in a block scope to avoid changing variable visibility
      hoisted_any = false
      if finally
        # Collect lvasgn names from body (use Array for JS compatibility)
        try_vars = []
        find_lvasgns = nil
        find_lvasgns = proc do |node|
          next unless ast_node?(node)
          if node.type == :lvasgn
            try_vars << node.children[0] unless try_vars.include?(node.children[0])
          end
          node.children.each { |c| find_lvasgns.call(c) } # Pragma: method
        end
        find_lvasgns.call(body) # Pragma: method

        # Collect lvar names from finally (use Array for JS compatibility)
        finally_vars = []
        find_lvars = nil
        find_lvars = proc do |node|
          next unless ast_node?(node)
          if node.type == :lvar
            finally_vars << node.children[0] unless finally_vars.include?(node.children[0])
          end
          node.children.each { |c| find_lvars.call(c) } # Pragma: method
        end
        find_lvars.call(finally) # Pragma: method

        # Hoist variables that appear in both (but not already declared)
        hoisted = try_vars.select { |var| finally_vars.include?(var) && !@vars[var] }
        if hoisted.length > 0
          hoisted_any = true
          puts '{'  # Open block scope to contain hoisted vars
          hoisted.each do |var|
            put "let #{var}#{@sep}"
            @vars[var] = true
          end
        end
      end

      # If retry is used, wrap in while(true) loop
      puts "while (true) {#{@nl}" if uses_retry

      # If else clause exists, we need a flag to track if no exception occurred
      if otherwise
        puts "let $no_exception = false#{@sep}"
      end

      puts "try {"; scope body
      # Set flag at end of try block if else clause exists
      puts "#{@sep}$no_exception = true" if otherwise
      # Add break after try body when using retry (to exit loop on success)
      puts "#{@sep}break" if uses_retry
      sput '}'

      if recovers

        if recovers.length == 1 and not recovers.first.children.first
          # find reference to exception ($!)
          walk = nil
          walk = proc do |ast|
            next nil unless ast_node?(ast)
            result = ast if ast.type === :gvar and ast.children.first == :$!
            ast.children.each do |child|
              result ||= walk.call(child) # Pragma: method # Pragma: logical
            end
            result
          end

          # single catch with no exception named
          if not var and not walk.call(@ast) # Pragma: method
            puts " catch {"
          else
            var ||= s(:gvar, :$EXCEPTION)
            put " catch ("; parse var; puts ") {"
          end
          scope recovers.first.children.last; sput '}'
        else
          catch_var = var || s(:gvar, :$EXCEPTION)
          put " catch ("; parse catch_var; puts ') {'

          first = true
          recovers.each do |recover|
            exceptions, recover_var, recovery = recover.children

            if exceptions

              put "} else " if not first
              first = false

              put  'if ('
              exceptions.children.each_with_index do |exception, index|
                put ' || ' unless index == 0
                if exception.type == :const and exception.children[0] == nil and
                  exception.children[1] == :String
                  put 'typeof '; parse catch_var; put ' == "string"'
                else
                  parse catch_var; put ' instanceof '; parse exception
                end
              end
              puts ') {'
            else
              puts '} else {'
            end

            # If this rescue clause uses a different variable, add an assignment
            if recover_var and recover_var != catch_var
              put 'var '; parse recover_var; put ' = '; parse catch_var; puts @sep
            end

            scope recovery; puts ''
          end

          if recovers.last.children.first
            puts "} else {"; put 'throw '; parse catch_var; puts ''
          end

          puts '}'; put '}'
        end
      end

      (puts ' finally {'; scope finally; sput '}') if finally

      # Execute else clause if no exception occurred
      if otherwise
        put "#{@sep}if ($no_exception) {#{@nl}"; scope otherwise; sput '}'
      end

      # Close while loop if using retry
      sput '}' if uses_retry

      # Close block scope if we hoisted variables
      sput '}' if hoisted_any
    end
  end
end
