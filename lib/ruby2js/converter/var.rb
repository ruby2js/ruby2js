module Ruby2JS
  class Converter

    # (lvar :a)
    # (gvar :$a)

    handle :lvar, :gvar do |var|
      put var
    end
  end
end
