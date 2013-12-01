require 'ruby2js'

module Ruby2JS
  module Filter
    module Functions
      include SEXP

      def on_send(node)
        target = process(node.children.first)
        args = process_all(node.children[2..-1])

        if node.children[1] == :to_s
          s(:send, target, :toString, *args)

        elsif node.children[1] == :to_i
          node.updated nil, [nil, :parseInt, target, *args]

        elsif node.children[1] == :to_f
          node.updated nil, [nil, :parseFloat, target, *args]

        elsif node.children[1] == :sub and node.children.length == 4
          source, method, before, after = node.children
          node.updated nil, [source, :replace, before, after]

        elsif node.children[1] == :gsub and node.children.length == 4
          source, method, before, after = node.children
          if before.type == :regexp
            before = s(:regexp, before.children.first,
              s(:regopt, :g, *before.children[1]))
          elsif before.type == :str
            before = s(:regexp, s(:str, Regexp.escape(before.children.first)),
              s(:regopt, :g))
          end
          node.updated nil, [source, :replace, before, after]

        elsif node.children[1] == :each
          if @each # disable `each` mapping, see jquery filter for an example
            super
          else
            node.updated nil, [target, :forEach, *args]
          end

        elsif node.children[0..1] == [nil, :puts]
          s(:send, s(:attr, nil, :console), :log, *node.children[2..-1])

        elsif node.children[1..-1] == [:first]
          node.updated nil, [node.children[0], :[], s(:int, 0)]

        elsif node.children[1..-1] == [:last]
          on_send node.updated nil, [node.children[0], :[], s(:int, -1)]

        elsif node.children[1] == :[] and node.children.length == 3
          source = node.children[0]
          index = node.children[2]

          # resolve negative literal indexes
          i = proc do |index|
            if index.type == :int and index.children.first < 0
              s(:send, s(:attr, source, :length), :-, 
                s(:int, -index.children.first))
            else
              index
            end
          end

          if index.type == :int and index.children.first < 0
            node.updated nil, [source, :[], i.(index)]

          elsif index.type == :erange
            start, finish = index.children
            node.updated nil, [source, :slice, i.(start), i.(finish)]

          elsif index.type == :irange
            start, finish = index.children
            start = i.(start)
            if finish.type == :int
              if finish.children.first == -1
                finish = s(:attr, source, :length)
              else
                finish = i.(s(:int, finish.children.first+1))
              end
            else
              finish = s(:send, finish, :+, s(:int, 1))
            end
            node.updated nil, [source, :slice, start, finish]

          else
            super
          end

        elsif node.children[1] == :each_with_index
          node.updated nil, [target, :forEach, *args]

        else
          super
        end
      end

      def on_block(node)
        call = node.children.first
        return super unless call.children.first == nil
        return super unless [:setInterval, :setTimeout].include? call.children[1]
        block = s(:block, s(:send, nil, :proc), *node.children[1..-1])
        call.updated nil, [*call.children[0..1], block, *call.children[2..-1]]
      end
    end

    DEFAULTS.push Functions
  end
end
