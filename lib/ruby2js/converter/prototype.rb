module Ruby2JS
  class Converter

    # (prototype expr) 

    # NOTE: prototype is a synthetic 

    handle :prototype do |expr|
      begin
        @block_this, @block_depth = false, 0
        prototype, @prototype = @prototype, true
        mark = output_location
        parse(expr)

        if @block_this
          insert mark, "let self = this#{@sep}"
        end
      ensure
        @prototype = prototype
        @block_this, @block_depth = nil, nil
      end
    end
  end
end
