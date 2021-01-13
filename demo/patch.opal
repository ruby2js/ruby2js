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

# update to 1.8.5
#   opal: https://github.com/opal/opal/blob/master/stdlib/racc/parser.rb
#   racc: https://github.com/ruby/racc/blob/master/lib/racc/parser.rb
# 
module Racc
  class Parser
    undef :_racc_evalact

    def _racc_evalact(act, arg)
      action_table, action_check, _, action_pointer,
      _,            _,            _, _,
      _,            _,            _, shift_n,
      reduce_n,     * = arg
      nerr = 0   # tmp

      if act > 0 and act < shift_n
        #
        # shift
        #
        if @racc_error_status > 0
          @racc_error_status -= 1 unless @racc_t <= 1 # error token or EOF
        end
        @racc_vstack.push @racc_val
        @racc_state.push act
        @racc_read_next = true
        if @yydebug
          @racc_tstack.push @racc_t
          racc_shift @racc_t, @racc_tstack, @racc_vstack
        end

      elsif act < 0 and act > -reduce_n
        #
        # reduce
        #
        code = catch(:racc_jump) {
          @racc_state.push _racc_do_reduce(arg, act)
          false
        }
        if code
          case code
          when 1 # yyerror
            @racc_user_yyerror = true   # user_yyerror
            return -reduce_n
          when 2 # yyaccept
            return shift_n
          else
            raise '[Racc Bug] unknown jump code'
          end
        end

      elsif act == shift_n
        #
        # accept
        #
        racc_accept if @yydebug
        throw :racc_end_parse, @racc_vstack[0]

      elsif act == -reduce_n
        #
        # error
        #
        case @racc_error_status
        when 0
          unless arg[21]    # user_yyerror
            nerr += 1
            on_error @racc_t, @racc_val, @racc_vstack
          end
        when 3
          if @racc_t == 0   # is $
            # We're at EOF, and another error occurred immediately after
            # attempting auto-recovery
            throw :racc_end_parse, nil
          end
          @racc_read_next = true
        end
        @racc_user_yyerror = false
        @racc_error_status = 3
        while true
          if i = action_pointer[@racc_state[-1]]
            i += 1   # error token
            if  i >= 0 and
                (act = action_table[i]) and
                action_check[i] == @racc_state[-1]
              break
            end
          end
          throw :racc_end_parse, nil if @racc_state.size <= 1
          @racc_state.pop
          @racc_vstack.pop
          if @yydebug
            @racc_tstack.pop
            racc_e_pop @racc_state, @racc_tstack, @racc_vstack
          end
        end
        return act

      else
        raise "[Racc Bug] unknown action #{act.inspect}"
      end

      racc_next_state(@racc_state[-1], @racc_state) if @yydebug

      nil
    end
  end
end
