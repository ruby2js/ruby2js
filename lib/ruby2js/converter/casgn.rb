module Ruby2JS
  class Converter

    # (casgn nil :a
    #   (int 1))

    handle :casgn do |cbase, var, value|
      multi_assign_declarations if @state == :statement

      begin
        cbase ||= @rbstack.map {|rb| rb[var]}.compact.last

        if @state == :statement and not cbase
          if es2015
            put "const "
          else
            put "var "
          end
        end

        (parse cbase; put '.') if cbase

        put "#{ var } = "; parse value
      ensure
        @vars[var] = true
      end
    end
  end
end
