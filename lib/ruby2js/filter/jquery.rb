require 'ruby2js'

module Ruby2JS
  module Filter
    module JQuery
      def initialize
        @each = true # disable each mapping, see functions filter
      end

      # map $$ to $
      def on_gvar(node)
        if node.children[0] == :$$
          node.updated nil, ['$']
        else
          super
        end
      end

      def on_send(node)
        if node.children[1] == :call
          target = process(node.children.first)
          if target.type == :gvar and target.children == ['$']
            s(:send, nil, '$', *process_all(node.children[2..-1]))
          else
            super
          end
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

    DEFAULTS.push JQuery
  end
end
