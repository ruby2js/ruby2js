require 'ruby2js'

module Ruby2JS
  module Filter
    module Return
      EXPRESSIONS = [ :array, :float, :hash, :if, :int, :lvar, :nil, :send ]

      def on_block(node)
        children = process_all(node.children)

        # find the block
        block = [children.pop || s(:nil)]
        while block.length == 1 and block.first.type == :begin
          block = block.first.children.dup
        end

        if EXPRESSIONS.include? block.last.type 
          block.push s(:return, block.pop)
        end

        if block.length == 1
          children.push block.first
        else
          children.push s(:begin, *block)
        end

        node.updated nil, children
      end

      def on_def(node)
        children = process_all(node.children[1..-1])
        children.unshift node.children.first

        # find the block
        block = [children.pop || s(:nil)]
        while block.length == 1 and block.first.type == :begin
          block = block.first.children.dup
        end

        if EXPRESSIONS.include? block.last.type 
          block.push s(:return, block.pop)
        end

        if block.length == 1
          children.push block.first
        else
          children.push s(:begin, *block)
        end

        node.updated nil, children
      end
      
      private

      # construct an AST Node
      def s(type, *args)
        Parser::AST::Node.new type, args
      end
    end
  end
end
