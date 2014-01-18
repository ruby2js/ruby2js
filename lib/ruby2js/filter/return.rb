require 'ruby2js'

module Ruby2JS
  module Filter
    module Return
      include SEXP

      EXPRESSIONS = [ :array, :float, :hash, :if, :int, :lvar, :nil, :send ]

      def on_block(node)
        children = process_all(node.children)

        children[-1] = s(:nil) if children.last == nil

        node.updated nil, [*node.children[0..1],
          s(:autoreturn, *children[2..-1])]
      end

      def on_def(node)
        children = process_all(node.children[1..-1])

        children[-1] = s(:nil) if children.last == nil

        node.updated nil, [node.children[0], children.first,
          s(:autoreturn, *children[1..-1])]
      end
    end

    DEFAULTS.push Return
  end
end
