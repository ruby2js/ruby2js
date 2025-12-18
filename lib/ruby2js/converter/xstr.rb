module Ruby2JS
  class Converter

    # (xstr
    #   (str 'a'))

    handle :xstr do |*children|
      if @binding
        str = eval capture { parse_all(*children) }
        if defined?(globalThis)
          # JavaScript context: binding is an object, use eval with Function
          # Create a function that has access to binding's properties
          keys = Object.keys(@binding)
          values = keys.map { |k| @binding[k] }
          func = Function.new(*keys, "return eval(#{str.inspect})")
          puts func.apply(nil, values).to_s
        else
          # Ruby context: binding is a Binding object
          puts @binding.eval(str).to_s
        end
      else
        raise SecurityError.new('Insecure operation, eval without binding option')
      end
    end
  end
end
