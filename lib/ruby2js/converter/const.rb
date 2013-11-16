module Ruby2JS
  class Converter

    # (const nil :C)

    handle :const do |receiver, name|
      "#{ parse receiver }#{ '.' if receiver }#{ name }"
    end
  end
end
