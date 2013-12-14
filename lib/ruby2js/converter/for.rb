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
    end
  end
end
