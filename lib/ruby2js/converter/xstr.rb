module Ruby2JS
  class Converter

    # (xstr
    #   (str 'a'))

    handle :xstr do |*children|
      if @binding
        str = eval capture { parse_all(*children) }
        puts @binding.eval(str).to_s
      else
        raise SecurityError.new('Insecure operation, eval without binding option')
      end
    end
  end
end
