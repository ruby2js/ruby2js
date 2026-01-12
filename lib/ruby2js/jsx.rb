# convert a JSX expression into Phlex-style Ruby statements
#
# Once the syntax is converted to pure Ruby statements,
# it can then be converted into either React or Phlex
# rendering instructions via the respective filters.

module Ruby2JS
  # HTML5 void elements (self-closing)
  JSX_VOID_ELEMENTS = %i[
    area base br col embed hr img input link meta param source track wbr
  ].freeze

  # Standard HTML5 elements
  JSX_HTML_ELEMENTS = %i[
    a abbr address article aside audio b bdi bdo blockquote body button
    canvas caption cite code colgroup data datalist dd del details dfn
    dialog div dl dt em fieldset figcaption figure footer form h1 h2 h3
    h4 h5 h6 head header hgroup html i iframe ins kbd label legend li
    main map mark menu meter nav noscript object ol optgroup option
    output p picture pre progress q rp rt ruby s samp script section
    select slot small span strong style sub summary sup table tbody td
    template textarea tfoot th thead time title tr u ul var video
  ].freeze

  JSX_ALL_ELEMENTS = (JSX_VOID_ELEMENTS + JSX_HTML_ELEMENTS).freeze

  def self.jsx2_rb(string)
    parser = JsxParser.new(string.chars)
    result = parser.parse()
    result.join("\n")
  end

  class JsxParser
    def initialize(stream)
      @stream = stream.respond_to?(:next) ? stream : ArrayIterator.new(stream)
      @state = :text
      @text = ''
      @result = []
      @element = ''
      @element_original = ''  # Keep original name with hyphens
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
        break if c.nil?

        if c == "\n"
          backtrace = ''
        else
          backtrace += c
        end

        case @state
        when :text
          if c == '<'
            @result << "plain \"#{@text.strip}\"" unless @text.strip.empty?
            if @tag_stack.empty?
              @result += self.class.new(@stream).parse(:element) # Pragma: array
              @state = :text
              @text = ''
            else
              @state = :element
              @element = ''
              @element_original = ''
              @attrs = {}
            end
          elsif c == '\\'
            @text += c + c
          elsif c == '{'
            @result << "plain \"#{@text}\"" unless @text.empty?
            @result += parse_expr # Pragma: array
            @text = ''
          else
            @text += c unless @text.empty? and c =~ /\s/
          end

        when :element
          if c == '/'
            if @element == ''
              @state = :close
              @element = ''
              @element_original = ''
            else
              @state = :void
            end
          elsif c == '>'
            @result << "#{element_call(@element, @element_original)} do"
            @tag_stack << [@element, @element_original]
            @state = :text
            @text = ''
          elsif c == ' ' or c == "\n"
            @state = :attr_name
            @attr_name = ''
            @attrs = {}
          elsif c == '-'
            @element += '_'
            @element_original += '-'
          elsif c =~ /^\w$/
            @element += c
            @element_original += c
          else
            raise SyntaxError.new("invalid character in element name: #{c.inspect}")
          end

        when :close
          if c == '>'
            tag_info = @tag_stack.last
            if tag_info && @element == tag_info[0]
              @tag_stack.pop
            elsif tag_info
              raise SyntaxError.new("missing close tag for: #{tag_info[0].inspect}")
            else
              raise SyntaxError.new("close tag for element that is not open: #{@element}")
            end

            @result << 'end'
            return @result if @tag_stack.empty?

            @state = :text
            @text = ''
          elsif c =~ /^\w$/
            @element += c
            @element_original += c
          elsif c == '-' && !@element.empty?
            @element += '_'
            @element_original += '-'
          elsif c != ' '
            raise SyntaxError.new("invalid character in element: #{c.inspect}")
          end

        when :void
          if c == '>'
            if @attrs.empty?
              @result << element_call(@element, @element_original)
            else
              @result << element_call(@element, @element_original, @attrs)
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
          elsif c == '-'
            @attr_name += '_'
          elsif c == '='
            @state = :attr_value
            @value = ''
          elsif c == '/' and @attr_name == ''
            @state = :void
          elsif c == ' ' or c == "\n" or c == '>'
            # Boolean attribute (no value) - treat as true
            if not @attr_name.empty?
              @attrs[@attr_name] = 'true'
              @attr_name = ''
            end
            if c == '>'
              @result << "#{element_call(@element, @element_original, @attrs)} do"
              @tag_stack << [@element, @element_original]
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
              @result << (@wrap_value ? "plain(#{@value})" : @value)
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
        raise SyntaxError.new("missing close tag for: #{@tag_stack.last[0].inspect}")
      end

      case @state
      when :text
        @result << "plain \"#{@text.strip}\"" unless @text.strip.empty?

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

      return @result
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

    # Generate the appropriate Phlex-style call for an element
    def element_call(element, original, attrs = nil)
      # Fragment (empty element name from <>)
      if element == ''
        return attrs ? "fragment(#{format_attrs(attrs)})" : "fragment"
      end

      # Check if it's a component (uppercase first letter)
      if element[0] =~ /[A-Z]/
        return component_call(element, attrs)
      end

      # Check if it's a custom element (has hyphen in original name)
      if original.include?('-')
        return custom_element_call(original, attrs)
      end

      # Standard HTML element
      html_element_call(element, attrs)
    end

    # Generate call for a React/Phlex component
    def component_call(name, attrs = nil)
      if attrs && !attrs.empty?
        "render #{name}.new(#{format_attrs(attrs)})"
      else
        "render #{name}.new"
      end
    end

    # Generate call for a custom element (web component)
    def custom_element_call(name, attrs = nil)
      if attrs && !attrs.empty?
        "tag(\"#{name}\", #{format_attrs(attrs)})"
      else
        "tag(\"#{name}\")"
      end
    end

    # Generate call for a standard HTML element
    def html_element_call(element, attrs = nil)
      if attrs && !attrs.empty?
        "#{element}(#{format_attrs(attrs)})"
      else
        element
      end
    end

    # Format attributes hash as Ruby keyword arguments
    def format_attrs(attrs)
      attrs.map { |name, value| "#{name}: #{value}" }.join(', ') # Pragma: entries
    end
  end

  # Iterator wrapper that provides next/peek interface for arrays.
  # Uses JS-style nil returns (not Ruby-style StopIteration exceptions)
  # so it works identically in Ruby, Opal, and transpiled JavaScript.
  class ArrayIterator
    def initialize(stream)
      # Use Array() for Ruby compatibility, transpiles to Array.from() in JS
      @stream = Array(stream)
    end

    def next
      return nil if @stream.empty?
      @stream.shift
    end

    def peek
      return nil if @stream.empty?
      @stream[0]
    end
  end
end
