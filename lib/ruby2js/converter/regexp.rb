module Ruby2JS
  class Converter

    # (regexp
    #   (str "x")
    #   (regopt :i))

    handle :regexp do |str, opt|
      str = str.children.first 
      if str.include? '/'
        if opt.children.empty?
          "new RegExp(#{ str.inspect })"
        else
          "new RegExp(#{ str.inspect }, #{ opt.children.join.inspect})"
        end
      else
        "/#{ str }/#{ opt.children.join }"
      end
    end
  end
end
