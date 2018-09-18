module Ruby2JS
  class Converter

    # (int 1)
    # (float 1.1)
    # (str "1"))

    handle :int, :float, :str do |value|
      put value.inspect
    end

    handle :octal do |value|
      put '0' + value.to_s(8)
    end
  end
end
