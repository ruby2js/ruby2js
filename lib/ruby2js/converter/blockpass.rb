module Ruby2JS
  class Converter

    # (block-pass
    #   (lvar :a))

    handle :block_pass do |arg|
      parse arg
    end
  end
end
