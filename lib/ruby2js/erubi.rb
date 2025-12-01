require 'erubi'

module Ruby2JS
  # Custom Erubi engine that produces parseable Ruby code for ERB templates.
  # Unlike Ruby's standard ERB, this handles block expressions (like form_for)
  # correctly by not wrapping them in parentheses.
  #
  # Usage:
  #   ruby_code = Ruby2JS::Erubi.new(template).src
  #   js_code = Ruby2JS.convert(ruby_code, filters: [:erb])
  #
  class Erubi < ::Erubi::Engine
    # Regex to detect block expressions (do |...| or { |...| at end of line)
    BLOCK_EXPR = /((\s|\))do|\{)(\s*\|[^|]*\|)?\s*\Z/

    def initialize(input, properties = {})
      # Use _buf as the buffer variable (matches HERB output)
      properties[:bufvar] ||= '_buf'
      properties[:preamble] ||= "#{properties[:bufvar]} = ::String.new;"
      properties[:postamble] ||= "#{properties[:bufvar]}.to_s"
      super
    end

    private

    def add_expression(indicator, code)
      if BLOCK_EXPR.match?(code)
        # Block expression - don't wrap in parens, let the block attach normally
        # Use .append= which works like << but allows block attachment
        src << " #{@bufvar}.append= " << code
      else
        # Regular expression - wrap in parens and call .to_s
        src << " #{@bufvar} << (" << code << ").to_s;"
      end
    end
  end
end
