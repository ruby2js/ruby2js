module Ruby2JS
  # Token wraps a string with AST location info for sourcemaps
  class Token
    attr_accessor :loc, :ast

    def initialize(string, ast)
      @string = string.to_s
      @ast = ast
      @loc = ast.location if ast && ast.respond_to?(:location)
    end

    def to_s
      @string
    end

    def to_str
      @string
    end

    def length
      @string.length
    end

    def empty?
      @string.empty?
    end

    def start_with?(*args)
      @string.start_with?(*args)
    end

    # JavaScript compatibility - functions filter converts start_with? -> startsWith
    def startsWith(*args)
      @string.start_with?(*args)
    end

    def end_with?(*args)
      @string.end_with?(*args)
    end

    # JavaScript compatibility - functions filter converts end_with? -> endsWith
    def endsWith(*args)
      @string.end_with?(*args)
    end

    def [](index) # Pragma: skip
      @string[index]
    end

    def at(index)
      # Handle negative indices for JS compatibility
      # In JS, string[negativeIndex] returns undefined, but at(negative) works
      if index < 0
        @string[index + @string.length]
      else
        @string[index]
      end
    end

    # Method for JavaScript compatibility (used by selfhost transpilation)
    # Using to_s! to avoid functions filter converting to_s->toString (causes infinite recursion)
    # Dummy underscore param forces this to be a method not a getter
    def toString(_=nil)
      self.to_s!
    end
  end

  # Line holds tokens for a single output line
  class Line
    attr_accessor :indent

    def initialize(*tokens)
      @tokens = tokens
      @indent = 0
    end

    def <<(token) # Pragma: skip
      @tokens << token # Pragma: array
      self
    end

    def append(token)
      @tokens.push(token)
      self
    end

    def push(*tokens)
      @tokens.push(*tokens)
      self
    end

    def pop()
      @tokens.pop
    end

    def first
      @tokens.first
    end

    def last
      @tokens.last
    end

    def length
      @tokens.length
    end

    def [](index) # Pragma: skip
      @tokens[index]
    end

    def at(index)
      @tokens[index]
    end

    def []=(index, value) # Pragma: skip
      @tokens[index] = value
    end

    def set(index, value)
      @tokens[index] = value
    end

    def find(&block)
      @tokens.find(&block)
    end

    def rindex(&block)
      @tokens.rindex(&block)
    end

    def each(&block)
      @tokens.each(&block)
    end

    def each_with_index(&block)
      @tokens.each_with_index(&block)
    end

    def map(&block)
      @tokens.map(&block)
    end

    def include?(item)
      @tokens.any? { |t| t.to_s == item.to_s }
    end

    def insert(index, *items)
      @tokens.insert(index, *items)
    end

    def slice!(range)
      @tokens.slice!(range)
    end

    def unshift(*items)
      @tokens.unshift(*items)
      self
    end

    def to_a
      @tokens.map(&:to_s)
    end

    def join(sep = '')
      @tokens.map(&:to_s).join(sep)
    end

    def comment?
      first_token = find { |token| !token.empty? }
      first_token && first_token.start_with?('//')
    end

    def empty?
      @tokens.all? { |token| token.empty? }
    end

    # Duplicate method for selfhost: _empty avoids functions filter's empty? -> length==0 transform
    def _empty
      @tokens.all? { |token| token.empty? }
    end

    def to_s
      # Use self._empty (no parens -> getter in JS) to avoid functions filter
      if self._empty
        ''
      elsif ['case ', 'default:'].include?(@tokens[0].to_s)
        ' ' * ([0, indent - 2].max) + join()
      elsif indent > 0
        ' ' * indent + join()
      else
        join()
      end
    end

    # Method for JavaScript compatibility (used by selfhost transpilation)
    # Using to_s! to avoid functions filter converting to_s->toString (causes infinite recursion)
    # Dummy underscore param forces this to be a method not a getter
    def toString(_=nil)
      self.to_s!
    end

    # For array-like concatenation: work += line
    def to_ary
      @tokens
    end
  end

  class Serializer
    attr_reader :timestamps
    attr_accessor :file_name

    def initialize
      @sep = '; '
      @nl = ''
      @ws = ' '

      @width = 80
      @indent = 0

      @lines = [Line.new]
      @line = @lines.last
      @timestamps = {}

      @ast = nil
      @file_name = ''
    end

    def timestamp(file)
      if file
        @timestamps[file] = File.mtime(file) if File.exist?(file)
      end
    end

    def uptodate?
      return false if @timestamps.empty?
      return @timestamps.all? { |file, mtime| File.mtime(file) == mtime }
    end

    def mtime
      return Time.now if @timestamps.empty?
      return @timestamps.values.max
    end

    def enable_vertical_whitespace
      @sep = ";\n"
      @nl = "\n"
      @ws = @nl
      @indent = 2
    end

    # indent multi-line parameter lists, array constants, blocks
    def reindent(lines)
      indent = 0
      lines.each do |line|
        first = line.find { |token| !token.empty? }
        if first
          last = line.at(line.rindex { |token| !token.empty? })
          if (first.start_with?('<') && line.include?('>')) ||
             (last.end_with?('>') && line.include?('<'))
            node = line.join[/.*?(<.*)/, 1]
            indent -= @indent if node.start_with?('</')

            line.indent = indent

            node = line.join[/.*(<.*)/, 1]
            indent += @indent unless node.include?('</') || node.include?('/>')
          else
            indent -= @indent if ')}]'.include?(first[0]) && indent >= @indent
            line.indent = indent
            indent += @indent if '({['.include?(last[-1])
          end
        else
          line.indent = indent
        end
      end
    end

    # add horizontal (indentation) and vertical (blank lines) whitespace
    def respace
      return if @indent == 0
      reindent @lines

      (@lines.length - 3).downto(0) do |i|
        if @lines[i].length == 0
          @lines.delete(i)
        elsif @lines[i + 1].comment? && !@lines[i].comment? &&
              @lines[i].indent == @lines[i + 1].indent
          # before a comment
          @lines.insert(i + 1, Line.new)
        elsif @lines[i].indent == @lines[i + 1].indent &&
              @lines[i + 1].indent < @lines[i + 2]&.indent.to_i &&
              !@lines[i].comment?
          # start of indented block
          @lines.insert(i + 1, Line.new)
        elsif @lines[i].indent > @lines[i + 1].indent &&
              @lines[i + 1].indent == @lines[i + 2]&.indent.to_i &&
              !@lines[i + 2]&.empty?
          # end of indented block
          @lines.insert(i + 2, Line.new)
        end
      end
    end

    # add a single token to the current line
    def put(string)
      unless string.is_a?(String) && string.include?("\n")
        @line << Token.new(string, @ast) # Pragma: array
      else
        parts = string.split("\n")
        first = parts.shift
        @line << Token.new(first, @ast) if first # Pragma: array
        parts.each { |part| @lines << Line.new(Token.new(part, @ast)) } # Pragma: array
        @lines << Line.new if string.end_with?("\n") # Pragma: array
        @line = @lines.last
      end
    end

    # add a single token to the current line without checking for newline
    # Named put_raw to avoid conflict with put (put! -> put in JS)
    def put_raw(string)
      @line << Token.new(string.gsub("\r", "\n"), @ast) # Pragma: array
    end

    # add a single token to the current line and then advance to next line
    def puts(string)
      unless string.is_a?(String) && string.include?("\n")
        @line << Token.new(string, @ast) # Pragma: array
      else
        put string
      end

      @line = Line.new
      @lines << @line # Pragma: array
    end

    # advance to next line and then add a single token to the current line
    def sput(string)
      unless string.is_a?(String) && string.include?("\n")
        @line = Line.new(Token.new(string, @ast))
        @lines << @line # Pragma: array
      else
        @line = Line.new
        @lines << @line # Pragma: array
        put string
      end
    end

    # current location: [line number, token number]
    def output_location
      [@lines.length - 1, @line.length]
    end

    # insert a line into the output
    def insert(mark, line)
      if mark.last == 0
        @lines.insert(mark.first, Line.new(Token.new(line.chomp, @ast)))
      else
        @lines[mark.first].insert(mark.last, Token.new(line, @ast))
      end
    end

    # capture (and remove) tokens from the output stream
    def capture(&block)
      mark = output_location
      block.() # Explicit call syntax for selfhost compatibility
      lines = @lines.slice!(mark.first + 1..-1) || []
      @line = @lines.last

      if lines.empty?
        lines = [@line.slice!(mark.last..-1) || []]
      elsif @line.length != mark.last
        lines.unshift(@line.slice!(mark.last..-1) || [])
      end

      lines.map { |l| l.respond_to?(:join) ? l.join : l.map(&:to_s).join }.join(@ws)
    end

    # wrap long statements in curly braces
    def wrap(open = '{', close = '}', &block)
      puts open
      mark = output_location
      block.() # Explicit call syntax for selfhost compatibility

      if @lines.length > mark.first + 1 ||
         @lines[mark.first - 1].join.length + @line.join.length >= @width
        sput close
      else
        @line = @lines[mark.first - 1]
        @line.pop  # remove the open brace
        popped = @lines.pop
        @line.push(*popped.to_ary)
      end
    end

    # compact small expressions into a single line
    def compact(&block)
      mark = output_location
      block.() # Explicit call syntax for selfhost compatibility
      return unless @lines.length - mark.first > 1
      return if @indent == 0

      # survey what we have to work with, keeping track of a possible
      # split of the last argument or value
      work = []
      len = 0
      trail = nil
      split = nil
      slice = @lines[mark.first..-1]
      reindent(slice)
      index = 0
      while index < slice.length
        line = slice[index]
        line << Token.new('', nil) if line.empty? # Pragma: array
        if line.first.start_with?('//')
          len += @width # comments are a deal breaker
        else
          if trail == line.indent && @indent > 0
            work.push(Token.new(' ', nil))
            len += 1
          end
          len += line.map(&:length).inject(0, &:+)
          work.push(*line.to_ary)

          if trail == @indent && line.indent == @indent
            split = [len, work.length, index]
            break if len >= @width - 10
          end
          trail = line.indent
        end
        index += 1
      end

      if len < @width - 10
        # full collapse
        @lines.slice!(mark.first..-1)
        @lines << Line.new(*work) # Pragma: array
        @line = @lines.last
      elsif split && split[0] < @width - 10
        if slice[split[2]].indent < slice[split[2] + 1]&.indent.to_i
          # collapse all but the last argument (typically a hash or function)
          close = slice.pop
          slice[-1].push(*close.to_ary)
          @lines[mark.first] = Line.new(*work[0..split[1] - 1])
          @lines.slice!(mark.first + 1..-1)
          slice[split[2] + 1..-1]&.each { |line| @lines << line } # Pragma: array
          @line = @lines.last
        end
      end
    end

    # Alias for selfhost transpilation (_compact avoids functions filter transformation)
    alias _compact compact

    # return the output as a string
    def to_s
      return @str if @str
      respace
      @str = @lines.map(&:to_s).join(@nl)
    end

    def to_str
      @str ||= to_s
    end

    BASE64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

    # https://docs.google.com/document/d/1U1RGAehQwRypUTovF1KRlpiOFze0b-_2gc6fAH0KY0k/edit
    # http://sokra.github.io/source-map-visualization/
    def vlq(*mark)
      if !@mark
        diffs = mark
        @mark = [0, 0, 0, 0, 0, 0]
      else
        if @mark[0] == mark[0]
          return if @mark[4] == mark[4] && @mark[3] == mark[3]
          @mappings += ',' unless @mappings == ''
        end

        diffs = mark.zip(@mark).map { |a, b| a - b }
      end

      while @mark[0] < mark[0]
        @mappings += ';'
        @mark[0] += 1
        diffs[1] = mark[1]
      end

      @mark[0...mark.length] = mark

      diffs[1..-1].each do |diff|
        if diff < 0
          data = (-diff << 1) + 1
        else
          data = diff << 1
        end

        if data <= 0b11111
          # workaround https://github.com/opal/opal/issues/575
          encoded = BASE64[data]
        else
          encoded = ''

          begin
            digit = data & 0b11111
            data >>= 5
            digit |= 0b100000 if data > 0
            encoded += BASE64[digit]
          end while data > 0
        end

        @mappings += encoded
      end
    end

    def sourcemap
      respace

      @mappings = ''
      sources = []
      names = []
      @mark = nil

      @lines.each_with_index do |line, row|
        col = line.indent
        line.each do |token|
          if token.respond_to?(:loc) && token.loc && token.loc.respond_to?(:expression) && token.loc.expression
            pos = token.loc.expression.begin_pos

            buffer = token.loc.expression.source_buffer
            source_index = sources.index(buffer)
            unless source_index
              source_index = sources.length
              timestamp buffer.name
              sources << buffer # Pragma: array
            end

            line_num = buffer.line_for_position(pos) - 1
            column = buffer.column_for_position(pos)

            name = nil
            if %i[lvasgn lvar].include?(token.ast.type)
              name = token.ast.children.first
            elsif %i[casgn const].include?(token.ast.type)
              name = token.ast.children[1] if token.ast.children.first.nil?
            end

            if name
              index = names.find_index(name)

              unless index
                index = names.length
                names << name # Pragma: array
              end

              vlq row, col, source_index, line_num, column, index
            else
              vlq row, col, source_index, line_num, column
            end
          end
          col += token.length
        end
      end

      @sourcemap = {
        version: 3,
        file: @file_name,
        sources: sources.map(&:name),
        names: names.map(&:to_s),
        mappings: @mappings
      }
    end
  end
end
