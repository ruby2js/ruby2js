module Ruby2JS
  class Converter

    # (regexp
    #   (str "x")
    #   (regopt :i))

    handle :regexp do |*parts, opt|
      # remove "extended" from list of options
      extended = false
      opts = opt.children
      if opts.include? :x
        opts = opts - [:x]
        extended = true
      end

      # remove whitespace and comments from extended regular expressions
      if extended
        parts.map! do |part|
          if part.type == :str
            str = part.children.first 
            str = str.gsub(/ #.*/,'').gsub(/\s/,'')
            s(:str, str)
          else
            part
          end
        end
      end

      # use slash syntax if there are few embedded slashes in the regexp
      if parts.all? {|part| part.type == :str}
        str = parts.map {|part| part.children.first}.join
        unless str.scan('/').length - str.scan("\\").length > 3
          return put "/#{ str.gsub('/', '\\/') }/#{ opts.join }"
        end
      end

      # create a new RegExp object
      put 'new RegExp('

      if parts.length == 1
        parse parts.first
      else
        parse s(:dstr, *parts)
      end

      unless opts.empty?
        put ", #{ opts.join.inspect}"
      end

      put ')'
    end
  end
end
