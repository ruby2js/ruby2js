module Ruby2JS
  class Converter

    # (int 1)
    # (float 1.1)
    # (str "1"))

    handle :int, :float, :str do |value|
      value.inspect
    end
  end
end
