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

      # gather length of string parts; if long enough, newlines will
      # not be escaped (poor man's HEREDOC)
      strings = children.select {|child| ast_node?(child) && child.type==:str}.
        map {|child| child.children.last}.join
      # Note: use (scan || []) pattern for JS compatibility where match() returns null
      heredoc = (strings.length > 40 and (strings.scan("\n") || []).length > 3)

      put '`'
      children.each do |child|
        # Skip nil/non-AST children
        next unless ast_node?(child)

        if child.type == :str
          str = child.children.first.inspect[1..-2].
            gsub('${', '$\{').gsub('`', '\\\`')
          str = str.gsub(/\\"/, '"') unless str.include? '\\\\'
          if heredoc
            put_raw str.gsub("\\n", "\n")
          else
            put str
          end
        elsif not (child.type == :begin and child.children.empty?)
          put '${'
          if @nullish_to_s
            # ${x ?? ''} - nil-safe interpolation matching Ruby's "#{nil}" => ""
            parse s(:nullish, child, s(:str, ''))
          else
            parse child
          end
          put '}'
        end
      end
      put '`'
    end
  end
end
