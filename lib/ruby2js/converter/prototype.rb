module Ruby2JS
  class Converter

    # (prototype expr) 

    # NOTE: prototype is a synthetic 

    handle :prototype do |expr|
      begin
        prototype, @prototype = @prototype, true
        parse(expr)
      ensure
        @prototype = prototype
      end
    end
  end
end
