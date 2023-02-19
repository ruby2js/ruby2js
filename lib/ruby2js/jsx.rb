# TODO: This feature is deprecated.
#
# convert a JSX expression into wunderbar statements
#
# Once the syntax is converted to pure Ruby statements,
# it can then be converted into either React or Vue
# rendering instructions.

module Ruby2JS
  def self.jsx2_rb(string)
    JsxParser.new(string.chars.each).parse.join("\n")
  end

  class JsxParser
    def initialize(stream)
      @stream = stream.respond_to?(:next) ? stream : OpalEnumerator.new(stream)
      @state = :text
      @text = ''
      @result = []
      @element = ''
      @attrs = {}
      @attr_name = ''
      @value = ''
      @tag_stack = []
      @expr_nesting = 0
      @wrap_value = true
    end

    def parse(state = :text, wrap_value = true)
      @wrap_value = wrap_value
      @state = state
      backtrace = ''
      prev = nil

      loop do
        c = @stream.next

        if c == "\n"
          backtrace = ''
        else
          backtrace += c
        end

        case @state
        when :text
          if c == '<'
            @result << "_(\"#{@text.strip}\")" unless @text.strip.empty?
            if @tag_stack.empty?
              @result += self.class.new(@stream).parse(:element)
              @state = :text
              @text = ''
            else
              @state = :element
              @element = ''
              @attrs = {}
            end
          elsif c == '\\'
            @text += c + c
          elsif c == '{'
            @result << "_(\"#{@text}\")" unless @text.empty?
            @result += parse_expr
            @text = ''
          else
            @text += c unless @text.empty? and c =~ /\s/
          end

        when :element
          if c == '/'
            if @element == ''
              @state = :close
              @element = ''
            else
              @state = :void
            end
          elsif c == '>'
            @result << "_#{@element} do"
            @tag_stack << @element
            @state = :text
            @text = ''
          elsif c == ' '
            @state = :attr_name
            @attr_name = ''
            @attrs = {}
          elsif c == '-'
            @element += '_'
          elsif c =~ /^\w$/
            @element += c
          else
            raise SyntaxError.new("invalid character in element name: #{c.inspect}")
          end

        when :close
          if c == '>'
            if @element == @tag_stack.last
              @tag_stack.pop
            elsif @tag_stack.last
              raise SyntaxError.new("missing close tag for: #{@tag_stack.last.inspect}")
            else
              raise SyntaxError.new("close tag for element that is not open: #{@element}")
            end

            @result << 'end'
            return @result if @tag_stack.empty?
          elsif c =~ /^\w$/
            @element += c
          elsif c != ' '
            raise SyntaxError.new("invalid character in element: #{c.inspect}")
          end

        when :void
          if c == '>'
            if @attrs.empty?
              @result << "_#{@element}"
            else
              @result << "_#{@element}(#{@attrs.map {|name, value| "#{name}: #{value}"}.join(' ')})"
            end
            return @result if @tag_stack.empty?

            @state = :text
            @text = ''
          elsif c != ' '
            raise SyntaxError.new('invalid character in element: "/"')
          end

        when :attr_name
          if c =~ /^\w$/
            @attr_name += c
          elsif c == '='
            @state = :attr_value
            @value = ''
          elsif c == '/' and @attr_name == ''
            @state = :void
          elsif c == ' ' or c == "\n" or c == '>'
            if not @attr_name.empty?
              raise SyntaxError.new("missing \"=\" after attribute #{@attr_name.inspect} " +
                "in element #{@element.inspect}")
            elsif c == '>'
              @result << "_#{@element}(#{@attrs.map {|name, value| "#{name}: #{value}"}.join(' ')}) do"
              @tag_stack << @element
              @state = :text
              @text = ''
            end
          else
            raise SyntaxError.new("invalid character in attribute name: #{c.inspect}")
          end

        when :attr_value
          if c == '"'
            @state = :dquote
          elsif c == "'"
            @state = :squote
          elsif c == '{'
            @attrs[@attr_name] = parse_value
            @state = :attr_name
            @attr_name = ''
          else
            raise SyntaxError.new("invalid value for attribute #{@attr_name.inspect} " +
              "in element #{@element.inspect}")
          end

        when :dquote
          if c == '"'
            @attrs[@attr_name] = '"' + @value + '"'
            @state = :attr_name
            @attr_name = ''
          elsif c == "\\"
            @value += c + c
          else
            @value += c
          end

        when :squote
          if c == "'"
            @attrs[@attr_name] = "'" + @value + "'"
            @state = :attr_name
            @attr_name = ''
          elsif c == "\\"
            @value += c + c
          else
            @value += c
          end

        when :expr
          if c == "}"
            if @expr_nesting > 0
              @value += c
              @expr_nesting -= 1
            else
              @result << (@wrap_value ? "_(#{@value})" : @value)
              return @result
            end
          elsif c == '<'
            if prev =~ /[\w\)\]\}]/
              @value += c # less than
            elsif prev == ' '
              if @stream.peek =~ /[a-zA-Z]/
                @value += parse_element.join(';')
                @wrap_value = false
              else
                @value += c
              end
            else
              @value += parse_element.join(';')
              @wrap_value = false
            end
          else
            @value += c
            @state = :expr_squote if c == "'"
            @state = :expr_dquote if c == '"'
            @expr_nesting += 1 if c == '{'
          end

        when :expr_squote
          @value += c
          if c == "\\"
            @state = :expr_squote_backslash
          elsif c == "'"
            @state = :expr
          end

        when :expr_squote_backslash
          @value += c
          @state = :expr_squote

        when :expr_dquote
          @value += c
          if c == "\\"
            @state = :expr_dquote_backslash
          elsif c == '#'
            @state = :expr_dquote_hash
          elsif c == '"'
            @state = :expr
          end

        when :expr_dquote_backslash
          @value += c
          @state = :expr_dquote

        when :expr_dquote_hash
          @value += c
          @value += parse_value + '}' if c == '{'
          @state = :expr_dquote

        else
          raise RangeError.new("internal state error in JSX: #{@state.inspect}")
        end

        prev = c
      end

      unless @tag_stack.empty?
        raise SyntaxError.new("missing close tag for: #{@tag_stack.last.inspect}")
      end

      case @state
      when :text
        @result << "_(\"#{@text.strip}\")" unless @text.strip.empty?

      when :element, :attr_name, :attr_value
        raise SyntaxError.new("unclosed element #{@element.inspect}")

      when :dquote, :squote, :expr_dquote, :expr_dquote_backslash, 
        :expr_squote, :expr_squote_backslash
        raise SyntaxError.new("unclosed quote")

      when :expr
        raise SyntaxError.new("unclosed value")

      else
        raise RangeError.new("internal state error in JSX: #{@state.inspect}")
      end

      @result
    rescue SyntaxError => e
      e.set_backtrace backtrace
      raise e
    end

    private

    def parse_value
      self.class.new(@stream).parse(:expr, false).join(',')
    end

    def parse_expr
      self.class.new(@stream).parse(:expr, true)
    end

    def parse_element
      self.class.new(@stream).parse(:element)
    end
  end

  # Opal's enumerator doesn't currently support next and peek methods.
  # Build a wrapper that adds those methods.
  class OpalEnumerator
    def initialize(stream)
      @stream = stream.to_a
    end

    def next
      raise StopIteration.new if @stream.empty?
      @stream.shift
    end

    def peek
      raise StopIteration.new if @stream.empty?
      @stream.first
    end
  end
end
