module Ruby2JS
  class Converter

    # (regexp
    #   (str "x")
    #   (regopt :i))

    handle :regexp do |*args|
      parts = args
      opt = parts.pop
      # remove "extended" from list of options
      extended = false
      opts = opt.children
      if opts.include? :x
        opts = opts.reject { |o| o == :x }
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

      # Ruby's /m flag makes . match newlines (JS /s does this)
      # Ruby's ^ and $ always match line boundaries (like JS /m)
      # So: Ruby /m with . should become JS /s (replacing /m)
      # Ruby without /m with ^ or $ should add JS /m
      has_ruby_m = opts.include?(:m) || opts.include?('m')
      if has_ruby_m
        # Check if regex contains . (but not escaped \. or inside [])
        all_str = parts.select { |p| p.type == :str }.map { |p| p.children[0] }.join
        if all_str.gsub(/\\./, '').gsub(/\[.*?\]/, '').include?('.')
          # Replace Ruby /m with JS /s for dot behavior
          opts = opts.reject { |o| o == :m || o == 'm' }
          opts = [*opts, :s] unless opts.include?(:s) || opts.include?('s')
        end
      end

      # Ruby ^ and $ match line boundaries by default; JS needs /m for this
      if parts.first.type == :str && parts.first.children[0].start_with?('^')
        unless opts.include?(:m) || opts.include?('m')
          opts = [*opts, :m]
        end
      elsif parts.last.type == :str && parts.last.children[0].end_with?('$')
        unless opts.include?(:m) || opts.include?('m')
          opts = [*opts, :m]
        end
      end

      # in Ruby regular expressions, /A is the start of the string
      if parts.first.type == :str and parts.first.children[0].start_with?('\A')
        parts = [s(:str, parts.first.children[0].sub('\A', '^'))].concat(
          parts[1..-1])
      end

      # in Ruby regular expressions, /z is the end of the string
      if parts.last.type == :str and parts.last.children[0].end_with?('\z')
        parts = parts[0..-2].concat(
          [s(:str, parts.last.children[0].sub('\z', '$'))])
      end

      # use slash syntax if there are few embedded slashes in the regexp
      if parts.all? {|part| part.type == :str}
        str = parts.map {|part| part.children.first}.join
        unless str.count('/') - str.count("\\") > 3
          return put "/#{ str.gsub('\\/', '/').gsub('/', '\\/') }/" +
            opts.join
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
