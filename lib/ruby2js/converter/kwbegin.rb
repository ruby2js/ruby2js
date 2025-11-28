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

      if block&.type == :ensure
        block, finally = block.children
      else
        finally = nil
      end

      if block and block.type == :rescue
        body, *recovers, otherwise = block.children

        # Collect all unique exception variables used across rescue clauses
        exception_vars = recovers.map {|r| r.children[1]}.compact.uniq

        # Use a common catch variable - prefer the first named one, or $EXCEPTION
        var = exception_vars.first

        if recovers[0..-2].any? {|recover| not recover.children[0]}
          raise Error.new(
            "additional recovers after catchall", @ast)
        end

        # Check if any rescue body contains a retry statement
        has_retry = nil
        has_retry = lambda do |node|
          next false unless node.is_a?(Parser::AST::Node)
          next true if node.type == :retry
          node.children.any? { |child| has_retry[child] }
        end
        uses_retry = recovers.any? { |recover| has_retry[recover.children.last] }
      else
        body = block
        uses_retry = false
      end

      if not recovers and not finally
        return scope s(:begin, *children)
      end

      # If retry is used, wrap in while(true) loop
      puts "while (true) {#{@nl}" if uses_retry

      # If else clause exists, we need a flag to track if no exception occurred
      if otherwise
        puts "#{es2015 ? 'let' : 'var'} $no_exception = false#{@sep}"
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
          walk = proc do |ast|
            result = ast if ast.type === :gvar and ast.children.first == :$!
            ast.children.each do |child|
              result ||= walk[child] if child.is_a? Parser::AST::Node
            end
            result
          end

          # single catch with no exception named
          if es2019 and not var and not walk[@ast]
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
                if exception == s(:const, nil, :String)
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
    end
  end
end
