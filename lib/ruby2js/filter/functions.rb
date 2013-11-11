require 'ruby2js'

module Ruby2JS
  module Filter
    module Functions

      # map $$ to $
      def on_gvar(node)
        if node.children[0] == :$$
          node.updated nil, ['$']
        else
          super
        end
      end

      def on_send(node)
        if node.children[1] == :to_s
          s(:send, node.children[0], :toString, *node.children[2..-1])

        elsif node.children[1] == :to_i
          node.updated nil, [nil, :parseInt, node.children[0], 
            *node.children[2..-1]]

        elsif node.children[1] == :to_f
          node.updated nil, [nil, :parseFloat, node.children[0], 
            *node.children[2..-1]]

        else
          super
        end
      end

      private

      # construct an AST Node
      def s(type, *args)
        Parser::AST::Node.new type, args
      end
    end
  end
end
