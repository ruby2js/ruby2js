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
          process node.updated nil, [nil, :parseFloat, target, *args]

        elsif node.children[1] == :sub and node.children.length == 4
          source, method, before, after = node.children
          process node.updated nil, [source, :replace, before, after]

        elsif node.children[1] == :gsub and node.children.length == 4
          source, method, before, after = node.children
          if before.type == :regexp
            before = s(:regexp, *before.children[0...-1],
              s(:regopt, :g, *before.children.last))
          elsif before.type == :str
            before = s(:regexp, s(:str, Regexp.escape(before.children.first)),
              s(:regopt, :g))
          end
          process node.updated nil, [source, :replace, before, after]

        elsif node.children[1] == :ord and node.children.length == 2
          if target.type == :str
            s(:int, target.children.last.ord)
          else
            node.updated nil, [target, :charCodeAt, s(:int, 0)]
          end

        elsif node.children[1] == :chr and node.children.length == 2
          if target.type == :int
            s(:str, target.children.last.chr)
          else
            node.updated nil, [s(:const, nil, :String), :fromCharCode, target]
          end

        elsif node.children[1] == :empty? and node.children.length == 2
          s(:send, s(:attr, target, :length), :==, s(:int, 0))

        elsif node.children[1] == :clear! and node.children.length == 2
          s(:send, target, :length=, s(:int, 0))

        elsif node.children[1] == :include? and node.children.length == 3
          s(:send, s(:send, target, :indexOf, args.first), :!=, s(:int, -1))

        elsif node.children[1] == :each
          if @each # disable `each` mapping, see jquery filter for an example
            super
          else
            node.updated nil, [target, :forEach, *args]
          end

        elsif node.children[0..1] == [nil, :puts]
          s(:send, s(:attr, nil, :console), :log, *args)

        elsif node.children[1..-1] == [:first]
          node.updated nil, [target, :[], s(:int, 0)]

        elsif node.children[1..-1] == [:last]
          on_send node.updated nil, [target, :[], s(:int, -1)]

        elsif node.children[1] == :[] and node.children.length == 3
          index = args.first

          # resolve negative literal indexes
          i = proc do |index|
            if index.type == :int and index.children.first < 0
              s(:send, s(:attr, target, :length), :-, 
                s(:int, -index.children.first))
            else
              index
            end
          end

          if index.type == :int and index.children.first < 0
            node.updated nil, [target, :[], i.(index)]

          elsif index.type == :erange
            start, finish = index.children
            node.updated nil, [target, :slice, i.(start), i.(finish)]

          elsif index.type == :irange
            start, finish = index.children
            start = i.(start)
            if finish.type == :int
              if finish.children.first == -1
                finish = s(:attr, target, :length)
              else
                finish = i.(s(:int, finish.children.first+1))
              end
            else
              finish = s(:send, finish, :+, s(:int, 1))
            end
            node.updated nil, [target, :slice, start, finish]

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
        if [:setInterval, :setTimeout].include? call.children[1]
          return super unless call.children.first == nil
          block = process s(:block, s(:send, nil, :proc), *node.children[1..-1])
          call.updated nil, [*call.children[0..1], block, *call.children[2..-1]]

        elsif [:sub, :gsub].include? call.children[1]
          return super if call.children.first == nil
          block = s(:block, s(:send, nil, :proc), *node.children[1..-1])
          process call.updated(nil, [*call.children, block])

        elsif call.children[1] == :any? and call.children.length == 2
          call = call.updated nil, [call.children.first, :some]
          node.updated nil, [call, *node.children[1..-1]]

        elsif call.children[1] == :all? and call.children.length == 2
          call = call.updated nil, [call.children.first, :every]
          node.updated nil, [call, *node.children[1..-1]]

        else
          super
        end
      end
    end

    DEFAULTS.push Functions
  end
end
