module Ruby2JS
  class Converter

    # (lvar :a)
    # (gvar :$a)

    handle :lvar, :gvar do |var|
      if var == :$!
        put '$EXCEPTION'
      else
        put var
      end
    end
  end
end
