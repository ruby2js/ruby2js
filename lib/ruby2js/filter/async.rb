require 'ruby2js'

module Ruby2JS
  module Filter
    module Async
      include SEXP

      def on_send(node)
        if node.children[0] == nil and node.children[1] == :async
          if node.children[2].type == :def
            # async def f(x) {...}
            node.children[2].updated :async

          elsif node.children[2].type == :defs
            # async def o.m(x) {...}
            node.children[2].updated :asyncs

          elsif node.children[2].type == :block
            block = node.children[2]

            if block.children[0].children.last == :lambda
              # async lambda {|x| ... }
              # async -> (x) { ... }
              block.updated(:async, [nil, block.children[1],
                s(:autoreturn, block.children[2])])

            elsif block.children[0].children.last == :proc
              # async proc {|x| ... }
              block.updated(:async, [nil, *block.children[1..-1]])

            elsif
              block.children[0].children[1] == :new and
              block.children[0].children[0] == s(:const, nil, :Proc)
            then
              # async Proc.new {|x| ... }
              block.updated(:async, [nil, *block.children[1..-1]])

            else
              super
            end
          else
            super
          end

        elsif node.children[0] == nil and node.children[1] == :await
          if node.children[2].type == :send
            # await f(x)
            node.children[2].updated(:await)

          elsif node.children[2].type == :block
            # await f(x) { ... }
            block = node.children[2]
            block.updated nil, [block.children[0].updated(:await),
              *block.children[1..-1]]

          else
            super
          end
        else
          super
        end
      end
    end

    DEFAULTS.push Async
  end
end
