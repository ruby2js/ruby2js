module Ruby2JS
  class Converter

    # (lvar :a)
    # (gvar :$a)

    handle :lvar, :gvar do |var|
      if var == :$!
        put '$EXCEPTION'
      elsif @ast.type == :lvar
        put jsvar(var)
      else
        put var
      end
    end
  end
end
