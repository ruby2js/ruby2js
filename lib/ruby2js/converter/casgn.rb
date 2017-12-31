module Ruby2JS
  class Converter

    # (casgn nil :a
    #   (int 1))

    handle :casgn do |cbase, var, value|
      begin
        if es2015
          put "const "
        else
          put "var "
        end

        (parse cbase; put '.') if cbase

        put "#{ var } = "; parse value
      ensure
        @vars[var] = true
      end
    end
  end
end
