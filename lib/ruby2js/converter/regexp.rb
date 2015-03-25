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
          return put "/#{ str }/#{ opts.join }"
        end
        put "new RegExp(#{ str.inspect }"
      else
        put 'new RegExp('

        parts.each_with_index do |part, index|
          put ' + ' unless index == 0

          if part.type == :str
            str = part.children.first 
            str = str.gsub(/ #.*/,'').gsub(/\s/,'') if extended
            put str.inspect
          else
            parse part
          end
        end
      end

      unless opts.empty?
        put ", #{ opts.join.inspect}"
      end

      put ')'
    end
  end
end
