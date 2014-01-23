require 'ruby2js'

module Ruby2JS
  module Filter
    module Functions
      include SEXP

      def on_send(node)
        target = node.children.first

        args = node.children[2..-1]

        if [:max, :min].include? node.children[1] and args.length == 0
          return super unless node.is_method?
          process s(:send, s(:attr, s(:const, nil, :Math), node.children[1]),
            :apply, s(:const, nil, :Math), target)

        elsif node.children[1] == :keys and  node.children.length == 2
          if node.is_method?
            process s(:send, s(:const, nil, :Object), :keys, target)
          else
            super
          end

        elsif node.children[1] == :to_s
          process s(:send, target, :toString, *args)

        elsif node.children[1] == :to_a
          process s(:send, target, :toArray, *args)

        elsif node.children[1] == :to_i
          process node.updated :send, [nil, :parseInt, target, *args]

        elsif node.children[1] == :to_f
          process node.updated :send, [nil, :parseFloat, target, *args]

        elsif node.children[1] == :sub and args.length == 2
          process node.updated nil, [target, :replace, *args]

        elsif [:sub!, :gsub!].include? node.children[1]
          method = :"#{node.children[1].to_s[0..-2]}"
          if target.type == :lvar
            process s(:lvasgn, target.children[0], s(:send,
              s(:lvar, target.children[0]), method, *node.children[2..-1]))
          elsif target.type == :send
            if target.children[0] == nil
              process s(:lvasgn, target.children[1], s(:send,
                s(:lvar, target.children[1]), method, *node.children[2..-1]))
            else
              process s(:send, target.children[0], :"#{target.children[1]}=", 
                s(:send, target, method, *node.children[2..-1]))
            end
          else
            super
          end

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
            process s(:int, target.children.last.ord)
          else
            process node.updated nil, [target, :charCodeAt, s(:int, 0)]
          end

        elsif node.children[1] == :chr and node.children.length == 2
          if target.type == :int
            process s(:str, target.children.last.chr)
          else
            process node.updated nil, [s(:const, nil, :String), :fromCharCode,
              target]
          end

        elsif node.children[1] == :empty? and node.children.length == 2
          process s(:send, s(:attr, target, :length), :==, s(:int, 0))

        elsif node.children[1] == :clear and node.children.length == 2
          if node.is_method?
            process s(:send, target, :length=, s(:int, 0))
          else
            super
          end

        elsif node.children[1] == :replace and node.children.length == 3
          process s(:begin, s(:send, target, :length=, s(:int, 0)),
             s(:send, target, :push, s(:splat, node.children[2])))

        elsif node.children[1] == :include? and node.children.length == 3
          process s(:send, s(:send, target, :indexOf, args.first), :!=,
            s(:int, -1))

        elsif node.children[1] == :each
          process node.updated nil, [target, :forEach, *args]

        elsif node.children[0..1] == [nil, :puts]
          process s(:send, s(:attr, nil, :console), :log, *args)

        elsif node.children[1] == :first
          if node.children.length == 2
            process node.updated nil, [target, :[], s(:int, 0)]
          elsif node.children.length == 3
            process on_send node.updated nil, [target, :[], s(:erange,
              s(:int, 0), node.children[2])]
          else
            super
          end

        elsif node.children[1] == :last
          if node.children.length == 2
            process on_send node.updated nil, [target, :[], s(:int, -1)]
          elsif node.children.length == 3
            process node.updated nil, [target, :slice,
              s(:send, s(:attr, target, :length), :-, node.children[2]),
              s(:attr, target, :length)]
          else
            super
          end


        elsif node.children[1] == :[]
          index = args.first

          # resolve negative literal indexes
          i = proc do |index|
            if index.type == :int and index.children.first < 0
              process s(:send, s(:attr, target, :length), :-, 
                s(:int, -index.children.first))
            else
              index
            end
          end

          if index.type == :regexp
            process s(:send, s(:send, target, :match, index), :[], 
              args[1] || s(:int, 0))

          elsif node.children.length != 3
            super

          elsif index.type == :int and index.children.first < 0
            process node.updated nil, [target, :[], i.(index)]

          elsif index.type == :erange
            start, finish = index.children
            process node.updated nil, [target, :slice, i.(start), i.(finish)]

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
            process node.updated nil, [target, :slice, start, finish]

          else
            super
          end

        elsif node.children[1] == :reverse! and node.is_method? 
          # input: a.reverse!
          # output: a.splice(0, a.length, *a.reverse)
          target = node.children.first
          process s(:send, target, :splice, s(:int, 0), 
            s(:attr, target, :length), s(:splat, s(:send, target, 
            :"#{node.children[1].to_s[0..-2]}", *node.children[2..-1])))

        elsif node.children[1] == :each_with_index
          process node.updated nil, [target, :forEach, *args]

        else
          super
        end
      end

      def on_block(node)
        call = node.children.first
        if [:setInterval, :setTimeout].include? call.children[1]
          return super unless call.children.first == nil
          block = process s(:block, s(:send, nil, :proc), *node.children[1..-1])
          on_send call.updated nil, [*call.children[0..1], block,
            *call.children[2..-1]]

        elsif [:sub, :gsub, :sub!, :gsub!].include? call.children[1]
          return super if call.children.first == nil
          block = s(:block, s(:send, nil, :proc), node.children[1],
            s(:autoreturn, *node.children[2..-1]))
          process call.updated(nil, [*call.children, block])

        elsif call.children[1] == :select and call.children.length == 2
          call = call.updated nil, [call.children.first, :filter]
          node.updated nil, [process(call), process(node.children[1]),
            s(:autoreturn, *process_all(node.children[2..-1]))]

        elsif call.children[1] == :any? and call.children.length == 2
          call = call.updated nil, [call.children.first, :some]
          node.updated nil, [process(call), process(node.children[1]),
            s(:autoreturn, *process_all(node.children[2..-1]))]

        elsif call.children[1] == :all? and call.children.length == 2
          call = call.updated nil, [call.children.first, :every]
          node.updated nil, [process(call), process(node.children[1]),
            s(:autoreturn, *process_all(node.children[2..-1]))]

        elsif call.children[1] == :map and call.children.length == 2
          node.updated nil, [process(call), process(node.children[1]),
            s(:autoreturn, *process_all(node.children[2..-1]))]

        elsif [:map!, :select!].include? call.children[1]
          # input: a.map! {expression}
          # output: a.splice(0, a.length, *a.map {expression})
          method = (call.children[1] == :map! ? :map : :select)
          target = call.children.first
          process s(:send, target, :splice, s(:splat, s(:send, s(:array, 
            s(:int, 0), s(:attr, target, :length)), :concat,
            s(:block, s(:send, target, method, *call.children[2..-1]),
            *node.children[1..-1]))))

        else
          super
        end
      end
    end

    DEFAULTS.push Functions
  end
end
