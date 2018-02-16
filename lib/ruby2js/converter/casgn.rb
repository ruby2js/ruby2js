module Ruby2JS
  class Converter

    # (casgn nil :a
    #   (int 1))

    handle :casgn do |cbase, var, value|
      multi_assign_declarations if @state == :statement

      begin
        if @state == :statement
          if es2015
            put "const "
          else
            put "var "
          end
        end

        cbase ||= @rbstack.map {|rb| rb[var]}.compact.last
        (parse cbase; put '.') if cbase

        put "#{ var } = "; parse value
      ensure
        @vars[var] = true
      end
    end
  end
end
