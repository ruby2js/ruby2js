module Ruby2JS
  class Converter

    # (while-post
    #   (true)
    #   (kwbegin
    #     (...)))

    handle :while_post do |condition, block|
      block = block.updated(:begin) if block.type == :kwbegin
      "do {#@nl#{ scope block }#@nl} while (#{ parse condition })"
    end
  end
end
