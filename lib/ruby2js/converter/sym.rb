module Ruby2JS
  class Converter

    # (sym :sym))

    handle :sym do |sym|
      sym.to_s.inspect
    end
  end
end
