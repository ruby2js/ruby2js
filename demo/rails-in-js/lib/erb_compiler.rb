# ERB to Ruby compiler for Rails-in-JS
# This produces Ruby code that can be transpiled to JavaScript.
# Both Ruby and selfhost builds use this same compiler for consistency.

class ErbCompiler
  def initialize(template)
    @template = template
  end

  # Compile ERB template to Ruby code
  # Format: _buf = ::String.new; _buf << 'literal'.freeze; _buf << ( expr ).to_s; ... _buf.to_s
  # Key: buffer operations use semicolons, code blocks use newlines
  def src
    ruby_code = "_buf = ::String.new;"
    pos = 0

    while pos < @template.length
      erb_start = @template.index("<%", pos)

      # Ruby's index returns nil, JS's indexOf returns -1
      if erb_start.nil? || erb_start < 0
        # No more ERB tags, add remaining text
        text = @template[pos..-1]
        ruby_code += " _buf << #{emit_ruby_string(text)};" if text && !text.empty?
        break
      end

      # Find end of ERB tag first to check if this is a code block
      erb_end = @template.index("%>", erb_start)
      # Ruby's index returns nil, JS's indexOf returns -1
      raise "Unclosed ERB tag" if erb_end.nil? || erb_end < 0

      tag = @template[(erb_start + 2)...erb_end]
      is_code_block = !tag.strip.start_with?("=") && !tag.strip.start_with?("-")

      # Add text before ERB tag
      if erb_start > pos
        text = @template[pos...erb_start]
        # For code blocks, strip trailing whitespace on the same line as <% %>
        # This matches Ruby Erubi behavior where leading indent before <% %> is not included
        if is_code_block
          if text.include?("\n")
            last_newline = text.rindex("\n")  # Ruby: rindex, JS: lastIndexOf
            after_newline = text[(last_newline + 1)..-1] || ""
            if after_newline =~ /^\s*$/
              text = text[0..last_newline]
            end
          end
        end
        ruby_code += " _buf << #{emit_ruby_string(text)};" if text && !text.empty?
      end

      # Handle -%> (trim trailing newline)
      trim_trailing = tag.end_with?("-")
      tag = tag[0...-1] if trim_trailing

      tag = tag.strip

      is_output_expr = false
      if tag.start_with?("=")
        # Output expression: <%= expr %>
        expr = tag[1..-1].strip
        ruby_code += " _buf << ( #{expr} ).to_s;"
        is_output_expr = true
      elsif tag.start_with?("-")
        # Unescaped output: <%- expr %> (same as <%= for our purposes)
        expr = tag[1..-1].strip
        ruby_code += " _buf << ( #{expr} ).to_s;"
        is_output_expr = true
      else
        # Code block: <% code %> - use newline, not semicolon
        ruby_code += " #{tag}\n"
      end

      pos = erb_end + 2
      # Trim trailing newline after code blocks (like Erubi does by default)
      if (trim_trailing || is_code_block) && pos < @template.length && @template[pos] == "\n"
        pos += 1
      end

      # For output expressions, if followed by a newline, add it as a separate literal
      # This matches Ruby Erubi which splits the newline after output expressions
      if is_output_expr && pos < @template.length && @template[pos] == "\n"
        ruby_code += " _buf << #{emit_ruby_string("\n")};"
        pos += 1
      end
    end

    ruby_code += "\n_buf.to_s"
    ruby_code
  end

  private

  # Emit a Ruby string literal using double quotes
  # Escape \, ", and newlines to keep strings on single lines
  def emit_ruby_string(str)
    escaped = str.gsub("\\", "\\\\").gsub('"', '\\"').gsub("\n", "\\n")
    "\"#{escaped}\""
  end
end
