module Ruby2JS
  class Converter

    # (if
    #   (true)
    #   (...)
    #   (...))

    handle :if do |condition, then_block, else_block|
      # return parse not condition if else_block and no then_block
      if else_block and not then_block
        return parse(s(:if, s(:not, condition), else_block, nil), @state) 
      end

      then_block ||= s(:nil)

      if @state == :statement
        begin
          inner, @inner = @inner, @ast

          # use short form when appropriate
          unless else_block or then_block.type == :begin
            # "Lexical declaration cannot appear in a single-statement context"
            if [:lvasgn, :gvasgn].include? then_block.type
              @vars[then_block.children.first] ||= :pending
            end

            put "if ("; parse condition; put ') '
            wrap { jscope then_block }
          else
            put "if ("; parse condition; puts ') {'
            jscope then_block
            sput '}'

            while else_block and else_block.type == :if
              condition, then_block, else_block = else_block.children
              if then_block
                put ' else if ('; parse condition; puts ') {'
                jscope then_block
                sput '}'
              else
                put ' else if ('; parse s(:not, condition); puts ') {'
                jscope else_block
                sput '}'
                else_block = nil
              end
            end

            if else_block
              puts ' else {'; jscope else_block; sput '}'
            end
          end
        ensure
          @inner = inner
        end
      else
        else_block ||= s(:nil)
        put '('; parse condition; put ' ? '; parse then_block
        put ' : '; parse else_block; put ')'
      end
    end
  end
end
