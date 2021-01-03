# convert a JSX expression into wunderbar statements
#
# Once the syntax is converted to pure Ruby statements,
# it can then be converted into either React or Vue
# rendering instructions.

module Ruby2JS
  def self.jsx2_rb(string)
    state = :text
    text = ''
    result = []
    element = ''
    attrs = {}
    attr_name = ''
    value = ''
    tag_stack = []
    expr_stack = []

    backtrace = ''

    for c in string.chars
      if c == "\n"
        backtrace = ''
      else
        backtrace += c
      end

      case state
      when :text
        if c == '<'
          result << "_ \"#{text.strip}\"" unless text.strip.empty?
          state = :element
          element = ''
          attrs = {}
        elsif c == '\\'
          text += c + c
        elsif c == '{'
          result << "_ \"#{text}\"" unless text.empty?
          text = ''
          expr_stack.push [state, '', attrs]
          state = :expr
        else
          text += c
        end

      when :element
        if c == '/'
          if element == ''
            state = :close
            element = ''
          else
            state = :void
          end
        elsif c == '>'
          result << "_#{element} do"
          tag_stack << element
          state = :text
          text = ''
        elsif c == ' '
          state = :attr_name
          attr_name = ''
          attrs = {}
        elsif c == '-'
          element += '_'
        elsif c =~ /^\w$/
          element += c
        else
          raise SyntaxError.new("invalid character in element name: #{c.inspect}")
        end

      when :close
        if c == '>'
          if element == tag_stack.last
            tag_stack.pop
          elsif tag_stack.last
            raise SyntaxError.new("missing close tag for: #{tag_stack.last.inspect}")
          else
            raise SyntaxError.new("close tag for element that is not open: #{element}")
          end

          result << 'end'
          state = :text
          text = ''
        elsif c =~ /^\w$/
          element += c
        elsif c != ' '
          raise SyntaxError.new("invalid character in element: #{c.inspect}")
        end

      when :void
        if c == '>'
          if attrs.empty?
            result << "_#{element}"
          else
            result << "_#{element} #{attrs.map {|name, value| "#{name}: #{value}"}.join(' ')}"
          end

          state = :text
          text = ''
        elsif c != ' '
          raise SyntaxError.new('invalid character in element: "/"')
        end

      when :attr_name
        if c =~ /^\w$/
          attr_name += c
        elsif c == '='
          state = :attr_value
          value = ''
        elsif c == '/' and attr_name == ''
          state = :void
        elsif c == ' ' or c == '>'
          if not attr_name.empty?
            raise SyntaxError.new("missing \"=\" after attribute #{attr_name.inspect} " +
              "in element #{element.inspect}")
          elsif c == '>'
            result << "_#{element} #{attrs.map {|name, value| "#{name}: #{value}"}.join(' ')} do"
            tag_stack << element
            state = :text
            text = ''
          end
        else
          raise SyntaxError.new("invalid character in attribute name: #{c.inspect}")
        end

      when :attr_value
        if c == '"'
          state = :dquote
        elsif c == "'"
          state = :squote
        elsif c == '{'
          expr_stack.push [state, attr_name, attrs]
          state = :expr
        else
          raise SyntaxError.new("invalid value for attribute #{attr_name.inspect} " +
            "in element #{element.inspect}")
        end

      when :dquote
        if c == '"'
          attrs[attr_name] = '"' + value + '"'
          state = :attr_name
          attr_name = ''
        elsif c == "\\"
          value += c + c
        else
          value += c
        end

      when :squote
        if c == "'"
          attrs[attr_name] = "'" + value + "'"
          state = :attr_name
          attr_name = ''
        elsif c == "\\"
          value += c + c
        else
          value += c
        end

      when :expr
        if c == "}"
          state, attr_name, attrs = expr_stack.pop
          if state == :attr_value
            attrs[attr_name] = value
            state = :attr_name
            attr_name = ''
          elsif state == :text
            result << "_ #{value}"
          elsif state == :expr_dquote_hash
            value += c
          else
            raise RangeError.new("internal state error in JSX: #{state.inspect}")
          end
        else
          value += c
          state = :expr_squote if c == "'"
          state = :expr_dquote if c == '"'
        end

      when :expr_squote
        value += c
        if c == "\\"
          state = :expr_squote_backslash
        elsif c == "'"
          state = :expr
        end

      when :expr_squote_backslash
        value += c
        state = :expr_squote

      when :expr_dquote
        value += c
        if c == "\\"
          state = :expr_dquote_backslash
        elsif c == '#'
          state = :expr_dquote_hash
        elsif c == '"'
          state = :expr
        end

      when :expr_dquote_backslash
        value += c
        state = :expr_dquote

      when :expr_dquote_hash
        value += c
        if c == '{'
          expr_stack.push [state, '', attrs]
          state = :expr
        else
          state = :expr_dquote
        end

      else
        raise RangeError.new("internal state error in JSX: #{state.inspect}")
      end
    end

    unless tag_stack.empty?
      raise SyntaxError.new("missing close tag for: #{tag_stack.last.inspect}")
    end

    case state
    when :text
      result << "_ \"#{text.strip}\"" unless text.strip.empty?

    when :element, :attr_name, :attr_value
      raise SyntaxError.new("unclosed element #{element.inspect}")

    when :dquote, :squote, :expr_dquote, :expr_dquote_backslash, 
      :expr_squote, :expr_squote_backslash
      raise SyntaxError.new("unclosed quote in #{element.inspect}")

    when :expr
      state, attr_name, attrs = expr_stack.pop
      if state == :attr_value
        raise SyntaxError.new("unclosed value for attribute #{attr_name.inspect} " +
          "in element #{element.inspect}")
      else
        raise SyntaxError.new("unclosed value in text")
      end

    else
      raise RangeError.new("internal state error in JSX: #{state.inspect}")
    end

    result.join("\n")

  rescue SyntaxError => e
    e.set_backtrace backtrace
    raise e
  end
end
