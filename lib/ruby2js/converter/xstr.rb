module Ruby2JS
  class Converter

    # (xstr
    #   (str 'a'))

    handle :xstr do |*children|
      str = eval children.map{ |child| parse child }.join
      if @binding
        @binding.eval(str).to_s
      else
        eval(str).to_s
      end
    end
  end
end
