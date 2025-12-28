module Ruby2JS
  class Converter

    # (hash
    #   (pair
    #     (sym :name)
    #     (str "value")))

    handle :hash do |*pairs|
      self._compact do
        singleton = pairs.length <= 1

        (singleton ? put('{') : puts('{'))

        index = 0
        while pairs.length > 0
          node = pairs.shift
          (singleton ? put(', ') : put(",#@ws")) unless index == 0
          index += 1

          if node.type == :kwsplat
            if node.children.first.type == :hash
              pairs.unshift(*node.children.first.children)
              index = 0
            else
              put '...'; parse node.children.first
            end

            next
          end

          node_comments = @comments.get(node)
          if node_comments && !node_comments.empty?
            (puts ''; singleton = false) if singleton
            comments(node).each {|comment| put comment}
          end

          begin
            block_depth,block_hash = @block_depth,false
            left, right = node.children

            if right.is_a?(Hash) or right.type == :block
              block_hash = true
              @block_depth = 0 unless @block_depth
            end

            if left.type == :prop
              if right[:get]
                get_comments = @comments.get(right[:get])
                if get_comments && !get_comments.empty?
                  (puts ''; singleton = false) if singleton
                  comments(right[:get]).each {|comment| put comment}
                end

                @prop = "get #{left.children[0]}"
                parse(right[:get])
                (singleton ? put(', ') : put(",#@ws")) if right[:set]
              end

              if right[:set]
                set_comments = @comments.get(right[:set])
                if set_comments && !set_comments.empty?
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
                  pair_child = pair.children.last
                  next unless ast_node?(pair_child)
                  if %i[block def defm async].include? pair_child.type
                    pair_comments = @comments.get(pair_child)
                    if pair_comments
                      (puts ''; singleton = false) if singleton
                      comments(pair_child).each do |comment|
                        put comment
                      end
                    end
                  end
                end
              end

              # check to see if anonymous function syntax can be used
              anonfn = (right and right.type == :block)
              if anonfn
                receiver, method = right.children[0].children
                if receiver
                  # Note: use explicit element comparison for JS compatibility (array == array compares refs in JS)
                  unless method == :new and receiver.children[0] == nil and receiver.children[1] == :Proc
                    anonfn = false
                  end
                elsif not [:lambda, :proc].include? method
                  anonfn = false
                end

                # use fat arrow syntax if block contains a reference to 'this'
                if anonfn and @class_name
                  walk = proc do |ast|
                    if ast == s(:self)
                      anonfn = false
                    elsif [:ivar, :ivasgn].include? ast.type
                      anonfn = false
                    elsif ast.type == :send and ast.children.first == nil 
                      method = ast.children.last if ast.children.length == 2
                      if @rbstack.any? {|rb| rb[method]} or method == :this
                        anonfn = false
                      end
                    end

                    ast.children.each do |child|
                      walk.call(child) if ast_node?(child)
                    end
                  end
                  walk.call(right)
                end
              end

              if \
                anonfn and 
                left.children.first.to_s =~ /\A[a-zA-Z_$][a-zA-Z_$0-9]*\z/
              then
                @prop = left.children.first
                parse right, :method
              elsif \
                left.type == :sym and (right.type == :lvar or
                (right.type == :send and right.children.first == nil)) and
                left.children.last == right.children.last
              then
                parse right
              elsif right.type == :defm and %i[sym str].include? left.type
                @prop = left.children.first.to_s
                parse right
              else
		if not [:str, :sym].include? left.type
		  put '['
		  parse left
		  put ']'
		elsif \
		  left.children.first.to_s =~ /\A[a-zA-Z_$][a-zA-Z_$0-9]*\z/
		then
		  put left.children.first
		else
		  parse left
		end

		put ': '; parse right
              end
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
