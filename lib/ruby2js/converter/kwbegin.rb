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
        raise Error.new("block else", @ast) if otherwise

        # Collect all unique exception variables used across rescue clauses
        exception_vars = recovers.map {|r| r.children[1]}.compact.uniq

        # Use a common catch variable - prefer the first named one, or $EXCEPTION
        var = exception_vars.first

        if recovers[0..-2].any? {|recover| not recover.children[0]}
          raise Error.new(
            "additional recovers after catchall", @ast)
        end
      else
        body = block
      end

      if not recovers and not finally
        return scope s(:begin, *children)
      end

      puts "try {"; scope body; sput '}'

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
    end
  end
end
