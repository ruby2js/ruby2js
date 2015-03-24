module Ruby2JS
  class Converter

    # (hash
    #   (pair
    #     (sym :name)
    #     (str "value")))

    handle :hash do |*pairs|
      compact do
        singleton = pairs.length <= 1

        (singleton ? put('{') : puts('{'))

        pairs.each_with_index do |node, index|
          raise NotImplementedError, "kwsplat" if node.type == :kwsplat

          (singleton ? put(', ') : put(",#@ws")) unless index == 0

          begin
            block_depth,block_this,block_hash = @block_depth,@block_this,false
            left, right = node.children

            if Hash === right or right.type == :block
              @block_depth, block_hash = 0, true
            end

            if left.type == :prop
              if right[:get]
                @prop = "get #{left.children[0]}"
                parse(right[:get])
                (singleton ? put(', ') : put(",#@ws")) if right[:set]
              end
              if right[:set]
                @prop = "set #{left.children[0]}"
                parse(right[:set])
              end
            else
              if 
                left.children.first.to_s =~ /\A[a-zA-Z_$][a-zA-Z_$0-9]*\Z/
              then
                put left.children.first
              else
                parse left
              end

              put ': '; parse right
            end

          ensure
            if block_hash
              @block_depth = block_depth
              @block_this = block_this
            end
          end
        end

        (singleton ? put('}') : sput('}'))
      end
    end
  end
end
