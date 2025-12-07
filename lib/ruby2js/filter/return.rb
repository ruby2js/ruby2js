require 'ruby2js'

module Ruby2JS
  module Filter
    module Return
      include SEXP

      EXPRESSIONS = [ :array, :float, :hash, :if, :int, :lvar, :nil, :send ]

      # Methods where blocks become arrow functions with implicit returns
      # These shouldn't get explicit return added
      IMPLICIT_RETURN_METHODS = %i[
        map select filter reject find find_all detect collect
        each each_with_index each_with_object
        reduce inject fold
        sort sort_by
        any? all? none? one?
        take_while drop_while
        group_by partition
        min_by max_by minmax_by
        forEach
      ].freeze

      def on_block(node)
        node = super
        return node unless node.type == :block

        call = node.children.first

        # Don't wrap Class.new blocks - they contain method definitions, not return values
        if call.type == :send and call.children[0]&.type == :const and
           call.children[0].children == [nil, :Class] and call.children[1] == :new
          return node
        end

        # Don't wrap blocks for methods that become arrow functions with implicit returns
        if call.type == :send && IMPLICIT_RETURN_METHODS.include?(call.children[1])
          return node
        end

        children = node.children.dup

        children[-1] = s(:nil) if children.last == nil

        node.updated nil, [*children[0..1],
          s(:autoreturn, *children[2..-1])]
      end

      def on_def(node)
        node = super
        return node unless node.type == :def or node.type == :deff or node.type == :defm
        return node if [:constructor, :initialize].include?(node.children.first)

        children = node.children[1..-1]

        children[-1] = s(:nil) if children.last == nil

        node.updated nil, [node.children[0], children.first,
          s(:autoreturn, *children[1..-1])]
      end

      def on_deff(node)
        on_def(node)
      end

      def on_defm(node)
        on_def(node)
      end

      def on_defs(node)
        node = super
        return node unless node.type == :defs
        children = node.children[3..-1]
        children[-1] = s(:nil) if children.last == nil
        node.updated nil, [*node.children[0..2], s(:autoreturn, *children)]
      end
    end

    DEFAULTS.push Return
  end
end
