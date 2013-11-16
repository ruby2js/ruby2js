module Ruby2JS
  class Converter

    # (while
    #   (true)
    #   (...))

    handle :while do |condition, block|
      "while (#{ parse condition }) {#@nl#{ scope block }#@nl}"
    end
  end
end
