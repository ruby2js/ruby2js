require 'ruby2js'

module Ruby2JS
  module Filter
    module Return
      include SEXP

      EXPRESSIONS = [ :array, :float, :hash, :if, :int, :lvar, :nil, :send ]

      def on_block(node)
        node = super
        return node unless node.type == :block
        children = node.children.dup

        children[-1] = s(:nil) if children.last == nil

        node.updated nil, [*children[0..1],
          s(:autoreturn, *children[2..-1])]
      end

      def on_def(node)
        node = super
        return node unless node.type == :def
        return node if [:constructor, :initialize].include?(node.children.first)

        children = node.children[1..-1]

        children[-1] = s(:nil) if children.last == nil

        node.updated nil, [node.children[0], children.first,
          s(:autoreturn, *children[1..-1])]
      end
    end

    DEFAULTS.push Return
  end
end
