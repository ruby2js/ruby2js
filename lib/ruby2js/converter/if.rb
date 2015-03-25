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
        # use short form when appropriate
        unless else_block or then_block.type == :begin
          put "if ("; parse condition; put ') '; wrap { scope then_block }
        else
          put "if ("; parse condition; puts ') {'; scope then_block; sput '}'
          while else_block and else_block.type == :if
            condition, then_block, else_block = else_block.children
            put ' else if ('; parse condition; puts ') {'
            scope then_block; sput '}'
          end
          (puts ' else {'; scope else_block; sput '}') if else_block
        end
      else
        else_block ||= s(:nil)
        put '('; parse condition; put ' ? '; parse then_block
        put ' : '; parse else_block; put ')'
      end
    end
  end
end
