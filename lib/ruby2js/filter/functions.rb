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
        target = process(node.children.first)
        args = process_all(node.children[2..-1])

        if node.children[1] == :to_s
          s(:send, target, :toString, *args)

        elsif node.children[1] == :to_i
          node.updated nil, [nil, :parseInt, target, *args]

        elsif node.children[1] == :to_f
          node.updated nil, [nil, :parseFloat, target, *args]

        elsif node.children[1] == :each
          node.updated nil, [target, :forEach, *args]

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
