module Ruby2JS
  class Converter

    # (const nil :C)

    handle :const do |receiver, name|
      # resolve anonymous receivers against rbstack
      receiver ||= @rbstack.map {|rb| rb[name]}.compact.last

      "#{ parse receiver }#{ '.' if receiver }#{ name }"
    end
  end
end
