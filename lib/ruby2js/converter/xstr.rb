module Ruby2JS
  class Converter

    # (xstr
    #   (str 'a'))

    handle :xstr do |*children|
      str = eval capture { parse_all(*children) }

      if @binding
        puts @binding.eval(str).to_s
      else
        puts eval(str).to_s
      end
    end
  end
end
