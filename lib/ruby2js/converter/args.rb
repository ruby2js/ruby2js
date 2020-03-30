module Ruby2JS
  class Converter

   # (args
   #   (arg :a)
   #   (restarg :b)
   #   (blockarg :c))

    handle :args do |*args|
      kwargs = []
      while args.last and 
        [:kwarg, :kwoptarg, :kwrestarg].include? args.last.type
        kwargs.unshift args.pop
      end

      if kwargs.length == 1 and kwargs.last.type == :kwrestarg
        args.push s(:arg, *kwargs.last.children)
      end

      unless kwargs.empty? or es2015
        raise NotImplementedError.new('Keyword args require ES2015')
      end

      parse_all(*args, join: ', ')
      if not kwargs.empty?
        put ', ' unless args.empty?
        put '{ '
        kwargs.each_with_index do |kw, index|
          put ', ' unless index == 0
          if kw.type == :kwarg
            put kw.children.first
          elsif kw.type == :kwoptarg
            put kw.children.first; put ' = '; parse kw.children.last
          elsif kw.type == :kwrestarg
            raise 'Rest arg requires ES2018' unless es2018
            put '...'; put kw.children.first
          end
        end
        put ' }'
      end
    end

    handle :mlhs do |*args|
      if es2015 or @jsx
        put '['
        parse_all(*args, join: ', ')
        put ']'
      else
        raise Error.new("destructuring requires ES2015", @ast)
      end
    end
  end
end
