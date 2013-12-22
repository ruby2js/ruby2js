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
        if expression.type == :irange
          "for (var #{parse var} = #{ parse expression.children.first }; " +
            "#{ parse var } <= #{ parse expression.children.last }; " +
            "#{ parse var }++) {#@nl#{ scope block }#@nl}"
        elsif expression.type == :erange
          "for (var #{parse var} = #{ parse expression.children.first }; " +
            "#{ parse var } < #{ parse expression.children.last }; " +
            "#{ parse var }++) {#@nl#{ scope block }#@nl}"
        else
          "for (var #{parse var} in #{ parse expression }) " +
            "{#@nl#{ scope block }#@nl}"
        end
      ensure
        @next_token = next_token
      end
    end
  end
end
