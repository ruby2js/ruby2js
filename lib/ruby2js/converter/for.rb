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
      parse s(:block,
        s(:send, expression, :forEach),
        s(:args, s(:arg, var.children.last)),
        block);
    end
  end
end
