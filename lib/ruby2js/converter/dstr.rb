module Ruby2JS
  class Converter

    # (dstr
    #   (str 'a')
    #   (...))

    # (dsym
    #   (str 'a')
    #   (...))

    handle :dstr, :dsym do |*children|
      if @state == :expression and children.empty?
        puts '""'
        return
      end

      if es2015
        # gather length of string parts; if long enough, newlines will
        # not be escaped (poor man's HEREDOC)
        strings = children.select {|child| child.type==:str}.
          map {|child| child.children.last}.join
        heredoc = (strings.length > 40 and strings.scan("\n").length > 3)

        put '`'
        children.each do |child|
          if child.type == :str
            str = child.children.first.inspect[1..-2].
              gsub('${', '$\{').gsub('`', '\\\`')
            str = str.gsub(/\\"/, '"') unless str.include? '\\\\'
            if heredoc
              put! str.gsub("\\n", "\n")
            else
              put str
            end
          elsif child != s(:begin)
            put '${'
            parse child
            put '}'
          end
        end
        put '`'

        return
      end

      children.each_with_index do |child, index|
        put ' + ' unless index == 0

        if child.type == :begin and child.children.length <= 1
          child = child.children.first || s(:str, '')
        end

        if child.type == :send
          op_index = operator_index child.children[1]
          if op_index >= operator_index(:+)
            group child
          else
            parse child
          end
        else
          parse child
        end
      end
    end
  end
end
