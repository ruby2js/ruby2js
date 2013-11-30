module Ruby2JS
  class Converter

    # (def (self) :foo
    #   (args)
    #   (...)

    handle :defs do |target, method, args, body|
      parse s(:send, target, "#{method}=", 
        s(:block, s(:send, nil, :lambda), args, body))
    end
  end
end
