module Ruby2JS
  class Converter

    # (sym :sym))

    handle :sym do |sym|
      put sym.to_s.inspect
    end
  end
end
