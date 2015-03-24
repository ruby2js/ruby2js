module Ruby2JS
  class Converter
    def init_serializer
      @lines = [[]]
      @line = @lines.last
    end

    def put(string)
      unless String === string and string.include? "\n"
        @line << string.to_s
      else
        parts = string.split("\n")
        @line << parts.shift
        @lines += parts.map {|part| [part]}
        @lines << [] if string.end_with?("\n")
        @line = @lines.last
      end
    end

    def puts(string)
      unless String === string and string.include? "\n"
        @line << string.to_s
      else
        put string
      end

      @line = []
      @lines << @line
    end

    def sput(string)
      unless String === string and string.include? "\n"
        @line = [string]
        @lines << @line
      else
        @line = []
        @lines << @line
        put string
      end
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
      [@lines.length, @line.length]
    end

    def insert(location, string)
      @lines[location.first-1].insert(location.last, string)
    end

    def capture(&block)
      mark = output_location
      block.call
      lines = @lines.slice!(mark.first..-1)
      @line = @lines.last

      if lines.empty?
        lines = [@line.slice!(mark.last..-1)]
      elsif @line.length != mark.last
        lines.unshift @line.slice!(mark.last..-1)
      end

      lines.map(&:join).join(@nl)
    end

    def wrap
      mark = output_location
      yield
      return if @lines.length == mark.first and @line.join.length < @width
      @lines.insert mark.first, @lines[mark.first-1].slice!(mark.last..-1)
      @lines[mark.first-1] << '{'
      sput '}'
    end

    def compact
      mark = output_location
      yield
      return unless @lines.length - mark.first >= 2

      len = @lines[mark.first-1..-1].map { |line| 
        line.map(&:length).reduce(&:+).to_i + 1
      }.reduce(&:+).to_i

      if len < @width - 10
        lines = @lines.slice!(mark.first-1..-1)
        @line = []
        lines.each_with_index do |line, index|
          @line << ' ' unless index <= 1 or index >= lines.length-1
          @line += line
        end
        @lines.push @line
      end
    end
  end
end
