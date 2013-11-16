module Ruby2JS
  class Converter

    # (until
    #   (true)
    #   (...))

    handle :until do |condition, block|
      parse s(:while, s(:send, condition, :!), block)
    end
  end
end
