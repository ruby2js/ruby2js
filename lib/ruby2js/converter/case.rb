module Ruby2JS
  class Converter

    # (case
    #   (send nil :a)
    #   (when
    #      (int 1)
    #      (...))
    #   (...))

    handle :case do |expr, *whens, other|
      begin
        if @state == :expression
          parse s(:kwbegin, @ast), @state
          return
        end

        inner, @inner = @inner, @ast

        has_range = whens.any? do |node| 
          node.children.any? {|child| [:irange, :erange].include? child&.type}
        end

        if has_range
          # https://stackoverflow.com/questions/5619832/switch-on-ranges-of-integers-in-javascript
          puts 'switch (true) {'
        else
          put 'switch ('; parse expr; puts ') {'
        end

        whens.each_with_index do |node, index|
          puts '' unless index == 0

          *values, code = node.children

          values.each do |value| 
            put 'case '; 
            if has_range
              if value.type == :irange
                parse expr; put ' >= '; parse value.children.first; put " && "
                parse expr; put ' <= '; parse value.children.last; put ":#@ws"
              elsif value.type == :erange
                parse expr; put ' >= '; parse value.children.first; put " && "
                parse expr; put ' < '; parse value.children.last; put ":#@ws"
              else
                parse expr; put ' == '; parse value; put ":#@ws"
              end
            else
              parse value; put ":#@ws"
            end
          end

          parse code, :statement
          last = code
          while last&.type == :begin
            last = last.children.last
          end

          if other or index < whens.length-1
            put "#{@sep}"
            put "break#@sep" unless last&.type == :return
          end
        end

        (put "#{@nl}default:#@ws"; parse other, :statement) if other

        sput '}'
      ensure
        @inner = inner
      end
    end
  end
end
