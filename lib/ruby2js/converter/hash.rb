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

          if not @comments[node].empty?
            (puts ''; singleton = false) if singleton
            comments(node).each {|comment| put comment}
          end

          begin
            block_depth,block_hash = @block_depth,false
            left, right = node.children

            if Hash === right or right.type == :block
              block_hash = true
              @block_depth = 0 unless @block_depth
            end

            if left.type == :prop
              if right[:get]
                unless @comments[right[:get]].empty?
                  (puts ''; singleton = false) if singleton
                  comments(right[:get]).each {|comment| put comment}
                end

                @prop = "get #{left.children[0]}"
                parse(right[:get])
                (singleton ? put(', ') : put(",#@ws")) if right[:set]
              end

              if right[:set]
                unless @comments[right[:set]].empty?
                  (puts ''; singleton = false) if singleton
                  comments(right[:set]).each {|comment| put comment}
                end

                @prop = "set #{left.children[0]}"
                parse(right[:set])
              end
            else
              # hoist get/set comments to definition of property
              if right.type == :hash
                right.children.each do |pair|
                next unless Parser::AST::Node === pair.children.last
                  if pair.children.last.type == :block
                    if @comments[pair.children.last]
                      (puts ''; singleton = false) if singleton
                      comments(pair.children.last).each do |comment|
                        put comment
                      end
                    end
                  end
                end
              end

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
            end
          end
        end

        (singleton ? put('}') : sput('}'))
      end
    end
  end
end
