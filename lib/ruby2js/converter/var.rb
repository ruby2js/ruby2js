module Ruby2JS
  class Converter

    # (lvar :a)
    # (gvar :$a)

    handle :lvar, :gvar do |var|
      var
    end
  end
end
