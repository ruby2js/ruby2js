module Ruby2JS
  class Converter

    # (case
    #   (send nil :a)
    #   (when
    #      (int 1)
    #      (...))
    #   (...))

    handle :case do |expr, *whens, other|
      put 'switch ('; parse expr; puts ') {'

      whens.each_with_index do |node, index|
        puts '' unless index == 0

        *values, code = node.children
        values.each {|value| put 'case '; parse value; put ":#@ws"}
        parse code, :statement; put "#{@sep}break#@sep"
      end

      (puts "#{@nl}default: "; parse other, :statement; puts '') if other

      sput '}'
    end
  end
end
