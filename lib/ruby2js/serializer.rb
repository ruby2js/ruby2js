module Ruby2JS
  class Converter
    def init_serializer
      @line = []
    end

    def put(string)
      @line << string
    end

    def puts(string='')
      @line << string + @nl
    end

    def sput(string)
      @line << @nl + string
    end

    def parse_all(*args)
      options = (Hash === args.last) ? args.pop : {}
      sep = options[:join].to_s
      state = options[:state] || :expression

      args.each_with_index do |arg, index|
        put sep unless index == 0
        parse arg, state
      end
    end

    def output_location
      # TODO
      @line.join.length
    end

    def insert(location, string)
      @line = [@line.join.insert(location, string)]
    end

    def capture(&block)
      mark = output_location
      block.call
      @line = [@line.join]
      @line.first.slice! mark..-1
    end

    def compact(mark)
      line = @line.join
      start = line.rindex("\n", mark) || -1
      if line.length - start < 70 and line[start+1..-1].split("\n").length >= 3
        @line = [line[0...start+1], line[start+1..-1]]
        @line.last.sub!(/\n/, '')
        @line.last[/(\n).*\Z/, 1] = ''
        @line.last.gsub!(/\n/, ' ')
      end
    end
  end
end
