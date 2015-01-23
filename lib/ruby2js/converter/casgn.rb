module Ruby2JS
  class Converter

    # (casgn nil :a
    #   (int 1))

    handle :casgn do |cbase, var, value|
      begin
        var = "#{ parse cbase }.var" if cbase
        "var #{ var } = #{ parse value }"
      ensure
        @vars[var] = true
      end
    end
  end
end
