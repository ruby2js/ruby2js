module Ruby2JS
  class Converter

    # (block
    #   (send nil :x)
    #   (args
    #     (arg :a))
    #   (lvar :a))

    handle :block do |call, args, block|
      block ||= s(:begin)
      function = s(:def, nil, args, block)
      parse s(:send, *call.children, function)
    end
  end
end
