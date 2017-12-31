module Ruby2JS
  class Converter

    # (xstr
    #   (str 'a'))
    # (for
    #   (lvasgn :i)
    #   (array
    #     (int 1))
    #   (...)

    handle :for do |var, expression, block|
      begin
        next_token, @next_token = @next_token, :continue
        put "for (#{es2015 ? 'let' : 'var'} "; parse var
        if [:irange, :erange].include? expression.type
          put ' = '; parse expression.children.first; put '; '; parse var
          (expression.type == :erange ? put(' < ') : put(' <= '))
          parse expression.children.last; put '; '; parse var; put '++'
        else
          put ' in '; parse expression; 
        end
        puts ') {'; scope block; sput '}'
      ensure
        @next_token = next_token
      end
    end
  end
end
