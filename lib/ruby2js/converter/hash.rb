module Ruby2JS
  class Converter

    # (hash
    #   (pair
    #     (sym :name)
    #     (str "value")))

    handle :hash do |*pairs|
      pairs.map! do |node|
        begin
          block_this, block_depth = @block_this, @block_depth
          @block_this, @block_depth = false, 0

          left, right = node.children
          if left.type == :prop
            result = []
            if right[:get]
              result << "get #{left.children[0]}#{
                parse(right[:get]).sub(/^function/,'')}"
            end
            if right[:set]
              result << "set #{left.children[0]}#{
                parse(right[:set]).sub(/^function/,'')}"
            end
            result
          else
            key = parse left
            key = $1 if key =~ /\A"([a-zA-Z_$][a-zA-Z_$0-9]*)"\Z/
            "#{key}: #{parse right}"
          end

        ensure
          @block_this, @block_depth = block_this, block_depth
        end
      end

      pairs.flatten!

      if pairs.map {|item| item.length+2}.reduce(&:+).to_i < @width-10
        "{#{ pairs.join(', ') }}"
      else
        "{#@nl#{ pairs.join(",#@ws") }#@nl}"
      end
    end
  end
end
