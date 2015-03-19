module Ruby2JS
  class Converter

    # (hash
    #   (pair
    #     (sym :name)
    #     (str "value")))

    handle :hash do |*pairs|
      comments_present = false

      pairs.map! do |node|
        raise NotImplementedError, "kwsplat" if node.type == :kwsplat

        begin
          block_depth, block_this, block_hash = @block_depth, @block_this, false
          left, right = node.children

          if Hash === right or right.type == :block
            @block_depth, block_hash = 0, true
          end

          if left.type == :prop
            result = []
            if right[:get]
              result << "get #{left.children[0]}#{
                parse(right[:get]).sub(/^function/,'')}"
              unless @comments[right[:get]].empty?
                comments_present = true
                result.last.insert 0, comments(right[:get]).join
              end
            end
            if right[:set]
              result << "set #{left.children[0]}#{
                parse(right[:set]).sub(/^function/,'')}"
              unless @comments[right[:set]].empty?
                comments_present = true
                result.last.insert 0, comments(right[:set]).join
              end
            end

          else
            key = parse left
            key = $1 if key =~ /\A"([a-zA-Z_$][a-zA-Z_$0-9]*)"\Z/

            result = "#{key}: #{parse right}"

            # hoist get/set comments to definition of property
            if right.type == :hash
              right.children.each do |pair|
                if pair.children.last.type == :block
                  if @comments[pair.children.last]
                    result.insert 0, comments(pair.children.last).join
                  end
                end
              end
            end
          end

          if not @comments[node].empty?
            comments_present = true
            if Array === result
              result.first.insert 0, comments(node).join
            else
              result.insert 0, comments(node).join
            end
          end

          result
        ensure
          if block_hash
            @block_depth = block_depth
            @block_this = block_this
          end
        end
      end

      pairs.flatten!

      if comments_present
        "{#@nl#{ pairs.join(",#@ws") }#@nl}"
      elsif pairs.map {|item| item.length+2}.reduce(&:+).to_i < @width-10
        "{#{ pairs.join(', ') }}"
      elsif pairs.length == 1
        "{#{ pairs.join(', ') }}"
      else
        "{#@nl#{ pairs.join(",#@ws") }#@nl}"
      end
    end
  end
end
