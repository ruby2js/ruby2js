# Simple ERB-to-JSX converter
#
# Converts ERB templates to JSX, transpiling Ruby expressions via Ruby2JS.
# Designed for simplicity and correctness on a well-defined subset of ERB.
#
# Supported constructs:
#   <% if cond %>...<% end %>
#   <% if cond %>...<% else %>...<% end %>
#   <% unless cond %>...<% end %>
#   <% items.each do |item| %>...<% end %>
#   <%= expr %>
#   {expr} in attributes (Ruby expressions)
#
# Usage:
#   ErbToJsx.convert(erb_template, options)
#
require 'strscan'

module Ruby2JS
  class ErbToJsx
    # Convert ERB template to JSX
    # Returns JSX string with Ruby expressions transpiled to JavaScript
    def self.convert(template, options = {})
      new(template, options).convert
    end

    def initialize(template, options = {})
      @template = template
      @options = options
      @scanner = StringScanner.new(template)
    end

    def convert
      result = parse_content
      # Wrap in fragment if multiple top-level elements
      if needs_fragment?(result)
        "<>#{result}</>"
      else
        result
      end
    end

    private

    # Parse content until we hit a stopping condition
    def parse_content(stop_at = nil)
      parts = []

      until @scanner.eos?
        # Check for stop conditions
        if stop_at
          case stop_at
          when :else_or_end
            break if @scanner.check(/<%\s*(else|end)\s*%>/)
          when :end
            break if @scanner.check(/<%\s*end\s*%>/)
          end
        end

        # Try to match various constructs
        if @scanner.check(/<%=/)
          parts << parse_erb_output
        elsif @scanner.check(/<%/)
          part = parse_erb_control
          parts << part if part
        elsif @scanner.check(/<[a-zA-Z]/)
          parts << parse_element
        elsif @scanner.check(/<\//)
          # Closing tag - stop parsing content
          break
        else
          text = parse_text
          parts << text if text && !text.strip.empty?
        end
      end

      parts.join
    end

    # Parse <%= expr %> - output tag
    def parse_erb_output
      @scanner.scan(/<%=\s*/)
      expr = scan_until_erb_close
      "{#{transpile(expr)}}"
    end

    # Parse <% ... %> - control tag
    def parse_erb_control
      @scanner.scan(/<%\s*/)
      code = scan_until_erb_close.strip

      case code
      when /^if\s+(.+)$/
        parse_if($1)
      when /^unless\s+(.+)$/
        parse_unless($1)
      when /^(\S+)\.each\s+do\s*\|([^|]+)\|$/
        parse_each($1, $2)
      when /^(\S+)\.map\s+do\s*\|([^|]+)\|$/
        parse_each($1, $2)
      when 'else', 'end'
        # These are handled by parent constructs
        nil
      else
        # Unknown control - skip
        nil
      end
    end

    # Parse if/else/end
    def parse_if(condition)
      then_content = parse_content(:else_or_end)

      if @scanner.scan(/<%\s*else\s*%>/)
        else_content = parse_content(:end)
        @scanner.scan(/<%\s*end\s*%>/)
        "{(#{transpile(condition)}) ? (#{then_content}) : (#{else_content})}"
      else
        @scanner.scan(/<%\s*end\s*%>/)
        "{(#{transpile(condition)}) && (#{then_content})}"
      end
    end

    # Parse unless/end
    def parse_unless(condition)
      content = parse_content(:end)
      @scanner.scan(/<%\s*end\s*%>/)
      "{!(#{transpile(condition)}) && (#{content})}"
    end

    # Parse each/end
    def parse_each(collection, var)
      var = var.strip
      content = parse_content(:end)
      @scanner.scan(/<%\s*end\s*%>/)
      "{#{transpile(collection)}.map(#{var} => (#{content}))}"
    end

    # Parse HTML element
    def parse_element
      @scanner.scan(/</)
      tag = @scanner.scan(/[a-zA-Z][a-zA-Z0-9-]*/)
      return '' unless tag

      # Parse attributes
      attrs = parse_attributes

      # Self-closing or void element?
      void_elements = %w[area base br col embed hr img input link meta param source track wbr]

      if @scanner.scan(/\s*\/\s*>/)
        # Explicit self-close
        "<#{tag}#{attrs} />"
      elsif @scanner.scan(/\s*>/)
        if void_elements.include?(tag.downcase)
          "<#{tag}#{attrs} />"
        else
          # Parse children
          children = parse_content
          # Consume closing tag
          @scanner.scan(/<\/#{tag}\s*>/)

          if children.strip.empty?
            "<#{tag}#{attrs} />"
          else
            "<#{tag}#{attrs}>#{children}</#{tag}>"
          end
        end
      else
        "<#{tag}#{attrs} />"
      end
    end

    # Parse element attributes
    def parse_attributes
      attrs = []

      loop do
        @scanner.scan(/\s+/)
        break if @scanner.check(/\/?>/)

        name = @scanner.scan(/[a-zA-Z_:][-a-zA-Z0-9_:.]*/)
        break unless name

        # Convert class to className for JSX
        jsx_name = (name == 'class') ? 'className' : name

        if @scanner.scan(/\s*=\s*/)
          if @scanner.scan(/"/)
            # Quoted string value
            value = @scanner.scan(/[^"]*/)
            @scanner.scan(/"/)
            attrs << "#{jsx_name}=\"#{value}\""
          elsif @scanner.scan(/'/)
            value = @scanner.scan(/[^']*/)
            @scanner.scan(/'/)
            attrs << "#{jsx_name}=\"#{value}\""
          elsif @scanner.scan(/\{/)
            # Expression value - Ruby expression
            expr = scan_balanced_braces
            attrs << "#{jsx_name}={#{transpile(expr)}}"
          else
            value = @scanner.scan(/[^\s>]+/)
            attrs << "#{jsx_name}=\"#{value}\""
          end
        else
          # Boolean attribute
          attrs << jsx_name
        end
      end

      attrs.empty? ? '' : ' ' + attrs.join(' ')
    end

    # Parse text content
    def parse_text
      text = ''
      until @scanner.eos?
        break if @scanner.check(/</) || @scanner.check(/<%/)
        char = @scanner.getch
        text += char if char
      end
      text
    end

    # Scan until %> and return content
    def scan_until_erb_close
      result = ''
      until @scanner.eos?
        if @scanner.scan(/%>/)
          return result.strip
        else
          char = @scanner.getch
          result += char if char
        end
      end
      result.strip
    end

    # Scan balanced braces, returning content (not including outer braces)
    def scan_balanced_braces
      depth = 1
      result = ''

      until @scanner.eos? || depth == 0
        char = @scanner.getch
        case char
        when '{'
          depth += 1
          result += char
        when '}'
          depth -= 1
          result += char if depth > 0
        else
          result += char if char
        end
      end

      result
    end

    # Transpile Ruby expression to JavaScript
    def transpile(ruby_expr)
      expr = ruby_expr.strip
      return expr if expr.empty?

      # Build options for Ruby2JS
      require 'ruby2js/filter/functions'
      require 'ruby2js/filter/camelCase'
      require 'ruby2js/filter/return'

      convert_options = {
        eslevel: @options.fetch(:eslevel, 2022),
        filters: [
          Ruby2JS::Filter::Functions,
          Ruby2JS::Filter::CamelCase,
          Ruby2JS::Filter::Return
        ]
      }

      begin
        # Wrap expression in a function to ensure it's treated as an expression
        # The return filter will add 'return' and we extract just the expression
        wrapped = "def _f_; #{expr}; end"
        result = Ruby2JS.convert(wrapped, convert_options).to_s

        # Extract the return expression from: function _f_() {return EXPR}
        if result =~ /\{return\s+(.+)\}$/
          $1.strip
        else
          # Fallback to original
          expr
        end
      rescue => e
        # If transpilation fails, return original (might already be valid JS)
        expr
      end
    end

    # Check if result needs fragment wrapper
    def needs_fragment?(result)
      # Simple heuristic: multiple top-level elements
      # Count root-level < that aren't </ or <>
      trimmed = result.strip
      return false if trimmed.empty?

      # If starts with { it's an expression, might need fragment
      # For now, assume single element is fine
      false
    end
  end
end
