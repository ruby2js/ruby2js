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
        scope, @scope = @scope, false
        mark = output_location

        put 'switch ('; parse expr; puts ') {'

        whens.each_with_index do |node, index|
          puts '' unless index == 0

          *values, code = node.children
          values.each {|value| put 'case '; parse value; put ":#@ws"}
          parse code, :statement
          put "#{@sep}break#@sep" if other or index < whens.length-1
        end

        (put "#{@nl}default:#@ws"; parse other, :statement) if other

        sput '}'

        if scope
          vars = @vars.select {|key, value| value == :pending}.keys
          unless vars.empty?
            insert mark, "var #{vars.join(', ')}#{@sep}"
            vars.each {|var| @vars[var] = true}
          end
        end
      ensure
        @scope = scope
      end
    end
  end
end
