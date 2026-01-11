# Convert JSX syntax directly to React.createElement JavaScript
#
# Unlike jsx2_rb which converts to Phlex-style Ruby, this outputs
# JavaScript directly, preserving expressions inside {} as-is.
#
# Usage:
#   Ruby2JS.rbx2_js('<div className="card">{title}</div>')
#   # => 'React.createElement("div", {className: "card"}, title)'

module Ruby2JS
  def self.rbx2_js(string, react_name: 'React')
    RbxParser.new(string.chars.each, react_name: react_name).parse
  end

  class RbxParser
    def initialize(stream, react_name: 'React')
      @stream = stream.respond_to?(:next) ? stream : OpalEnumerator.new(stream)
      @react_name = react_name
      @state = :text
      @text = ''
      @element = ''
      @attrs = {}
      @attr_name = ''
      @value = ''
      @tag_stack = []
      @expr_nesting = 0
    end

    def parse
      result = parse_content
      result.length == 1 ? result.first : wrap_fragment(result)
    end

    private

    def parse_content(initial_state: :text, single_element: false)
      results = []
      @text = ''
      @state = initial_state
      initial_stack_depth = @tag_stack.length

      loop do
        c = @stream.next

        case @state
        when :text
          if c == '<'
            results << text_node(@text) unless @text.strip.empty?
            @text = ''
            peek = @stream.peek rescue nil
            if peek == '/'
              @stream.next # consume '/'
              @state = :close_tag
              @element = ''
            else
              @state = :open_tag
              @element = ''
              @attrs = {}
            end
          elsif c == '{'
            results << text_node(@text) unless @text.strip.empty?
            @text = ''
            results << parse_expression
          else
            @text += c
          end

        when :open_tag
          if c == '>'
            # Opening tag complete, parse children
            # Save element/attrs before parsing children (they get overwritten by nested elements)
            saved_element, saved_attrs = @element, @attrs
            @tag_stack << @element
            children = parse_content
            results << create_element(saved_element, saved_attrs, children)
            # Return if we just completed a single element parse (for nested JSX in expressions)
            return results if single_element && @tag_stack.length == initial_stack_depth
          elsif c == '/'
            # Self-closing tag
            peek = @stream.next rescue nil
            if peek == '>'
              results << create_element(@element, @attrs, [])
              return results if @tag_stack.empty? || (single_element && @tag_stack.length == initial_stack_depth)
              @state = :text  # Continue parsing siblings
            else
              raise SyntaxError, "Expected '>' after '/'"
            end
          elsif c == ' ' || c == "\n" || c == "\t"
            @state = :attr_name if @element != ''
            @attr_name = ''
          elsif c == '-'
            @element += '-'
          else
            @element += c
          end

        when :close_tag
          if c == '>'
            if @tag_stack.empty? || @tag_stack.last != @element
              raise SyntaxError, "Mismatched closing tag: </#{@element}>"
            end
            @tag_stack.pop
            @state = :text
            return results
          elsif c != ' ' && c != "\n" && c != "\t"
            @element += c
          end

        when :attr_name
          if c == '='
            @state = :attr_value
          elsif c == '>'
            @attrs[@attr_name] = 'true' unless @attr_name.empty?
            # Save element/attrs before parsing children (they get overwritten by nested elements)
            saved_element, saved_attrs = @element, @attrs
            @tag_stack << @element
            children = parse_content
            results << create_element(saved_element, saved_attrs, children)
            # Return if we just completed a single element parse (for nested JSX in expressions)
            return results if single_element && @tag_stack.length == initial_stack_depth
          elsif c == '/'
            @attrs[@attr_name] = 'true' unless @attr_name.empty?
            peek = @stream.next rescue nil
            if peek == '>'
              results << create_element(@element, @attrs, [])
              return results if @tag_stack.empty? || (single_element && @tag_stack.length == initial_stack_depth)
              @state = :text  # Continue parsing siblings
            end
          elsif c == ' ' || c == "\n" || c == "\t"
            @attrs[@attr_name] = 'true' unless @attr_name.empty?
            @attr_name = ''
          elsif c == '-'
            @attr_name += '-'
          else
            @attr_name += c
          end

        when :attr_value
          if c == '"'
            @state = :attr_value_dquote
            @value = ''
          elsif c == "'"
            @state = :attr_value_squote
            @value = ''
          elsif c == '{'
            @attrs[@attr_name] = parse_expression
            @state = :attr_name
            @attr_name = ''
          else
            raise SyntaxError, "Expected quote or { for attribute value"
          end

        when :attr_value_dquote
          if c == '"'
            @attrs[@attr_name] = "\"#{escape_js_string(@value)}\""
            @state = :attr_name
            @attr_name = ''
          elsif c == '\\'
            @value += c + (@stream.next rescue '')
          else
            @value += c
          end

        when :attr_value_squote
          if c == "'"
            @attrs[@attr_name] = "\"#{escape_js_string(@value)}\""
            @state = :attr_name
            @attr_name = ''
          elsif c == '\\'
            @value += c + (@stream.next rescue '')
          else
            @value += c
          end
        end
      end

      # End of input
      results << text_node(@text) unless @text.strip.empty?
      results
    rescue StopIteration
      results << text_node(@text) unless @text.strip.empty?
      results
    end

    def parse_expression
      expr = ''
      nesting = 1

      loop do
        c = @stream.next

        if c == '{'
          nesting += 1
          expr += c
        elsif c == '}'
          nesting -= 1
          if nesting == 0
            return expr.strip
          else
            expr += c
          end
        elsif c == '"'
          expr += c
          expr += parse_string_until('"')
        elsif c == "'"
          expr += c
          expr += parse_string_until("'")
        elsif c == '`'
          expr += c
          expr += parse_template_string
        elsif c == '<'
          # Nested JSX
          peek = @stream.peek rescue nil
          if peek =~ /[a-zA-Z]/
            expr += parse_nested_jsx
          else
            expr += c
          end
        else
          expr += c
        end
      end
    rescue StopIteration
      raise SyntaxError, "Unclosed expression"
    end

    def parse_string_until(quote)
      result = ''
      loop do
        c = @stream.next
        result += c
        return result if c == quote && result[-2] != '\\'
      end
    rescue StopIteration
      raise SyntaxError, "Unclosed string"
    end

    def parse_template_string
      result = ''
      loop do
        c = @stream.next
        result += c
        if c == '`' && result[-2] != '\\'
          return result
        elsif c == '$'
          peek = @stream.next rescue nil
          if peek == '{'
            result += peek
            nesting = 1
            while nesting > 0
              c = @stream.next
              result += c
              nesting += 1 if c == '{'
              nesting -= 1 if c == '}'
            end
          else
            result += peek if peek
          end
        end
      end
    rescue StopIteration
      raise SyntaxError, "Unclosed template string"
    end

    def parse_nested_jsx
      # Parse nested JSX starting from :open_tag state
      # We've already consumed '<' and peeked the next letter
      @element = ''
      @attrs = {}
      result = parse_content(initial_state: :open_tag, single_element: true)
      result.length == 1 ? result.first : wrap_fragment(result)
    end

    def create_element(tag, attrs, children)
      # Check if it's a component (uppercase) or HTML element (lowercase)
      tag_arg = if tag[0] =~ /[A-Z]/
        tag
      elsif tag == ''
        "#{@react_name}.Fragment"
      else
        "\"#{tag}\""
      end

      # Build props object
      props = build_props(attrs)

      # Build children
      children_args = children.compact

      parts = [tag_arg, props]
      parts.concat(children_args) unless children_args.empty?

      "#{@react_name}.createElement(#{parts.join(', ')})"
    end

    def build_props(attrs)
      return 'null' if attrs.empty?

      pairs = attrs.map do |key, value|
        # Convert class to className
        js_key = key == 'class' ? 'className' : key
        # Convert kebab-case to camelCase for DOM properties
        if js_key.include?('-') && js_key[0] =~ /[a-z]/
          js_key = js_key.gsub(/-([a-z])/) { $1.upcase }
        end
        "#{js_key}: #{value}"
      end

      "{#{pairs.join(', ')}}"
    end

    def text_node(text)
      cleaned = text.gsub(/\s+/, ' ')
      return nil if cleaned.strip.empty?
      "\"#{escape_js_string(cleaned)}\""
    end

    def wrap_fragment(elements)
      children = elements.compact
      return children.first if children.length == 1
      "#{@react_name}.createElement(#{@react_name}.Fragment, null, #{children.join(', ')})"
    end

    def escape_js_string(str)
      str.gsub('\\', '\\\\').gsub('"', '\\"').gsub("\n", '\\n').gsub("\r", '\\r')
    end
  end
end
