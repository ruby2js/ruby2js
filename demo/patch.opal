require 'corelib/string/unpack'

# https://github.com/opal/opal/blob/master/lib/opal/parser/patch.rb
class Parser::Lexer
  def source_buffer=(source_buffer)
    @source_buffer = source_buffer

    if @source_buffer
      source = @source_buffer.source
      # Force UTF8 unpacking even if JS works with UTF-16/UCS-2
      # See: https://mathiasbynens.be/notes/javascript-encoding
      @source_pts = source.unpack('U*')
    else
      @source_pts = nil
    end
  end
end

class Parser::Lexer::Literal
  undef :extend_string

  def extend_string(string, ts, te)
    @buffer_s ||= ts
    @buffer_e = te

    # Patch for opal-parser, original:
    # @buffer << string
    @buffer += string
  end
end

class Parser::Source::Buffer
  def source_lines
    @lines ||= begin
      lines = @source.lines.to_a
      lines << '' if @source.end_with?("\n")
      lines.map { |line| line.chomp("\n") }
    end
  end
end

# https://github.com/whitequark/parser/issues/784
module Parser
  class Diagnostic
    undef :render_line

    def render_line(range, ellipsis=false, range_end=false)
      source_line    = range.source_line
      highlight_line = [' '] * source_line.length

      @highlights.each do |highlight|
        line_range = range.source_buffer.line_range(range.line)
        if highlight = highlight.intersect(line_range)
          highlight_line[highlight.column_range] = ['~'] * highlight.size
        end
      end

      if range.is?("\n")
        highlight_line << "^"
      else
        if !range_end && range.size >= 1
          highlight_line[range.column_range] = ['^'] + ['~'] * (range.size - 1)
        else
          highlight_line[range.column_range] = ['~'] * range.size
        end
      end

      highlight_line += %w(. . .) if ellipsis
      highlight_line = highlight_line.join

      [source_line, highlight_line].
        map { |line| "#{range.source_buffer.name}:#{range.line}: #{line}" }
    end
  end
end
