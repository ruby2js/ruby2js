module Ruby2JS
  class Converter

    # (xstr
    #   (str 'a'))
    # (for
    #   (lvasgn :i)
    #   (array
    #     (int 1))
    #   (...)

    handle :for, :for_of do |var, expression, block|
      if @jsx and @ast.type == :for_of
        parse s(:block, s(:send, expression, :map),
         s(:args, s(:arg, var.children[0])),
         s(:autoreturn, block))
        return
      end

      begin
        vars = @vars.dup
        next_token, @next_token = @next_token, :continue
        put "for (let "; parse var
        if expression and [:irange, :erange].include? expression.type
          put ' = '; parse expression.children.first; put '; '; parse var
          (expression.type == :erange ? put(' < ') : put(' <= '))
          parse expression.children.last; put '; '; parse var; put '++'
        else
          put (@ast.type==:for_of ? ' of ' : ' in '); parse expression; 
        end
        puts ') {'; redoable block; sput '}'
      ensure
        @next_token = next_token
        @vars = vars
      end
    end
  end
end
