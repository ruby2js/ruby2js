module Ruby2JS
  class Serializer
    def initialize
      @sep = '; '
      @nl = ''
      @ws = ' '

      @width = 80

      @lines = [[]]
      @line = @lines.last
    end

    def enable_vertical_whitespace
      @sep = ";\n"
      @nl = "\n"
      @ws = @nl
    end

    # add a single token to the current line
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

    # add a single token to the current line and then advance to next line
    def puts(string)
      unless String === string and string.include? "\n"
        @line << string.to_s
      else
        put string
      end

      @line = []
      @lines << @line
    end

    # advance to next line and then add a single token to the current line
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

    # current location: [line number, token number]
    def output_location
      [@lines.length-1, @line.length]
    end

    # insert a line into the output
    def insert(mark, line)
      @lines[mark.first].insert(mark.last, line)
    end

    # capture (and remove) tokens from the output stream
    def capture(&block)
      mark = output_location
      block.call
      lines = @lines.slice!(mark.first+1..-1)
      @line = @lines.last

      if lines.empty?
        lines = [@line.slice!(mark.last..-1)]
      elsif @line.length != mark.last
        lines.unshift @line.slice!(mark.last..-1), [@ws]
      end

      lines.map(&:join).join(@nl)
    end

    # wrap long statements in curly braces
    def wrap
      mark = output_location
      yield
      return if @lines.length == mark.first+1 and @line.join.length < @width
      @lines.insert mark.first+1, @lines[mark.first].slice!(mark.last..-1)
      @lines[mark.first] << '{'
      sput '}'
    end

    # compact small expressions into a single line
    def compact
      mark = output_location
      yield
      return unless @lines.length - mark.first+1 >= 2
      return if @lines.any? {|line| line.first.to_s.start_with? '//'}

      len = @lines[mark.first..-1].map { |line|
        line.map(&:length).reduce(&:+).to_i + 1
      }.reduce(&:+).to_i

      if len < @width - 10
        lines = @lines.slice!(mark.first..-1)
        @line = []
        lines.each_with_index do |line, index|
          @line << ' ' unless index <= 1 or index >= lines.length-1
          @line += line
        end
        @lines.push @line
      end
    end

    # return the output as a string
    def serialize
      @lines.map(&:join).join(@nl)
    end
  end
end
