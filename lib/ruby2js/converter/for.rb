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
        parse s(:block,
          s(:send, expression, :forEach),
          s(:args, s(:arg, var.children.last)),
          block);
      end
    end
  end
end
