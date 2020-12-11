module Ruby2JS
  class Converter

    # (xstr
    #   (str 'a'))

    handle :xstr do |*children|
      str = eval capture { parse_all(*children) }

      if @binding
        puts @binding.eval(str).to_s
      else
        raise SecurityError.new('Insecure operation, eval without binding option')
      end
    end
  end
end
