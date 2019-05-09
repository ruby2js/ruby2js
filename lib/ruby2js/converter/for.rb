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
      begin
        vars = @vars.dup
        next_token, @next_token = @next_token, :continue
        put "for (#{es2015 ? 'let' : 'var'} "; parse var
        if expression and [:irange, :erange].include? expression.type
          put ' = '; parse expression.children.first; put '; '; parse var
          (expression.type == :erange ? put(' < ') : put(' <= '))
          parse expression.children.last; put '; '; parse var; put '++'
        else
          put (@ast.type==:for_of ? ' of ' : ' in '); parse expression; 
        end
        puts ') {'; scope block; sput '}'
      ensure
        @next_token = next_token
        @vars = vars if es2015
      end
    end
  end
end
