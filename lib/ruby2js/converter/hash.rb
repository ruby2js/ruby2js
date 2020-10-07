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

        index = 0
        while pairs.length > 0
          node = pairs.shift
          (singleton ? put(', ') : put(",#@ws")) unless index == 0
          index += 1

          if node.type == :kwsplat
            if es2018
              if node.children.first.type == :hash
                pairs.unshift(*node.children.first.children)
                index = 0
              else
                puts '...'; parse node.children.first
              end

              next
            else
              raise Error.new("kwsplat", @ast)
            end
          end

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
                  if [:block, :def, :async].include? pair.children.last.type
                    if @comments[pair.children.last]
                      (puts ''; singleton = false) if singleton
                      comments(pair.children.last).each do |comment|
                        put comment
                      end
                    end
                  end
                end
              end

              # check to see if es2015 anonymous function syntax can be used
              anonfn = (es2015 and right and right.type == :block)
              if anonfn
                receiver, method = right.children[0].children
                if receiver
                  unless method == :new and receiver.children == [nil, :Proc]
                    anonfn = false
                  end
                elsif not [:lambda, :proc].include? method
                  anonfn = false
                end

                # use fat arrow syntax if block contains a reference to 'this'
                if anonfn
                  walk = proc do |ast|
                    if ast == s(:self)
                      anonfn = false
                    elsif ast.type == :send and ast.children.first == nil 
                      method = ast.children.last if ast.children.length == 2
                      if @rbstack.any? {|rb| rb[method]} or method == :this
                        anonfn = false
                      end
                    end

                    ast.children.each do |child|
                      walk[child] if child.is_a? Parser::AST::Node
                    end
                  end
                  walk[right]
                end
              end

              if \
                anonfn and 
                left.children.first.to_s =~ /\A[a-zA-Z_$][a-zA-Z_$0-9]*\Z/
              then
                @prop = left.children.first
                parse right, :method
              elsif \
                es2015 and left.type == :sym and right.type == :lvar and
                left.children == right.children
              then
                parse right 
              else
		if not [:str, :sym].include? left.type and es2015
		  put '['
		  parse left
		  put ']'
		elsif \
		  left.children.first.to_s =~ /\A[a-zA-Z_$][a-zA-Z_$0-9]*\Z/
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
