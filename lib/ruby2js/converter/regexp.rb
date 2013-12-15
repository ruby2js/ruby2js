module Ruby2JS
  class Converter

    # (regexp
    #   (str "x")
    #   (regopt :i))

    handle :regexp do |*parts, opt|
      extended = false
      opts = opt.children
      if opts.include? :x
        opts = opts.dup - [:x]
        extended = true
      end

      if parts.all? {|part| part.type == :str}
        str = parts.map {|part| part.children.first}.join
        str = str.gsub(/ #.*/,'').gsub(/\s/,'') if extended
        unless str.include? '/'
          return "/#{ str }/#{ opts.join }"
        end
        str = str.inspect
      else
        parts.map! do |part|
          if part.type == :str
            str = part.children.first 
            str = str.gsub(/ #.*/,'').gsub(/\s/,'') if extended
            str.inspect
          else
            parse part
          end
        end
        str = parts.join(' + ')
      end

      if opts.empty?
        "new RegExp(#{ str })"
      else
        "new RegExp(#{ str }, #{ opts.join.inspect})"
      end
    end
  end
end
