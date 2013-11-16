module Ruby2JS
  class Converter

    # (until-post
    #   (true)
    #   (kwbegin
    #     (...)))

    handle :until_post do |condition, block|
      parse s(:while_post, s(:send, condition, :!), block)
    end
  end
end
