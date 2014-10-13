require 'ruby2js'

module Ruby2JS
  module Filter
    module Functions
      include SEXP

      VAR_TO_ASSIGN = {
        lvar: :lvasgn,
        ivar: :ivasgn,
        cvar: :cvasgn,
        gvar: :gvasgn
      }

      def on_send(node)
        target, method, *args = node.children

        if [:max, :min].include? node.children[1] and args.length == 0
          return super unless node.is_method?
          process s(:send, s(:attr, s(:const, nil, :Math), node.children[1]),
            :apply, s(:const, nil, :Math), target)

        elsif method == :keys and args.length == 0 and node.is_method?
          process s(:send, s(:const, nil, :Object), :keys, target)

        elsif method == :delete and args.length == 1
          process s(:undef, s(:send, target, :[], args.first))

        elsif method == :to_s
          process s(:send, target, :toString, *args)

        elsif method == :to_a
          process s(:send, target, :toArray, *args)

        elsif method == :to_i
          process node.updated :send, [nil, :parseInt, target, *args]

        elsif method == :to_f
          process node.updated :send, [nil, :parseFloat, target, *args]

        elsif method == :sub and args.length == 2
          process node.updated nil, [target, :replace, *args]

        elsif [:sub!, :gsub!].include? method
          method = :"#{method.to_s[0..-2]}"
          if VAR_TO_ASSIGN.keys.include? target.type
            process s(VAR_TO_ASSIGN[target.type], target.children[0], 
              s(:send, target, method, *node.children[2..-1]))
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

        elsif method == :gsub and args.length == 2
          before, after = args
          if before.type == :regexp
            before = s(:regexp, *before.children[0...-1],
              s(:regopt, :g, *before.children.last))
          elsif before.type == :str
            before = s(:regexp, s(:str, Regexp.escape(before.children.first)),
              s(:regopt, :g))
          end
          process node.updated nil, [target, :replace, before, after]

        elsif method == :ord and args.length == 0
          if target.type == :str
            process s(:int, target.children.last.ord)
          else
            process node.updated nil, [target, :charCodeAt, s(:int, 0)]
          end

        elsif method == :chr and args.length == 0
          if target.type == :int
            process s(:str, target.children.last.chr)
          else
            process node.updated nil, [s(:const, nil, :String), :fromCharCode,
              target]
          end

        elsif method == :empty? and args.length == 0
          process s(:send, s(:attr, target, :length), :==, s(:int, 0))

        elsif method == :nil? and args.length == 0
          process s(:send, target, :==, s(:nil))

        elsif [:start_with?, :end_with?].include? method and args.length == 1
          if args.first.type == :str
            length = s(:int, args.first.children.first.length)
          else
            length = s(:attr, *args, :length)
          end

          if method == :start_with?
            process s(:send, s(:send, target, :substring, s(:int, 0), 
              length), :==, *args)
          else
            process s(:send, s(:send, target, :slice, 
              s(:send, length, :-@)), :==, *args)
          end

        elsif method == :clear and args.length == 0 and node.is_method?
          process s(:send, target, :length=, s(:int, 0))

        elsif method == :replace and args.length == 1
          process s(:begin, s(:send, target, :length=, s(:int, 0)),
             s(:send, target, :push, s(:splat, node.children[2])))

        elsif method == :include? and args.length == 1
          process s(:send, s(:send, target, :indexOf, args.first), :!=,
            s(:int, -1))

        elsif method == :each
          process node.updated nil, [target, :forEach, *args]

        elsif method == :downcase and args.length == 0
          process node.updated nil, [target, :toLowerCase]

        elsif method == :upcase and args.length == 0
          process node.updated nil, [target, :toUpperCase]

        elsif node.children[0..1] == [nil, :puts]
          process s(:send, s(:attr, nil, :console), :log, *args)

        elsif method == :first
          if node.children.length == 2
            process node.updated nil, [target, :[], s(:int, 0)]
          elsif node.children.length == 3
            process on_send node.updated nil, [target, :[], s(:erange,
              s(:int, 0), node.children[2])]
          else
            super
          end

        elsif method == :last
          if node.children.length == 2
            process on_send node.updated nil, [target, :[], s(:int, -1)]
          elsif node.children.length == 3
            process node.updated nil, [target, :slice,
              s(:send, s(:attr, target, :length), :-, node.children[2]),
              s(:attr, target, :length)]
          else
            super
          end


        elsif method == :[]
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

        elsif method == :reverse! and node.is_method? 
          # input: a.reverse!
          # output: a.splice(0, a.length, *a.reverse)
          target = node.children.first
          process s(:send, target, :splice, s(:int, 0), 
            s(:attr, target, :length), s(:splat, s(:send, target, 
            :"#{node.children[1].to_s[0..-2]}", *node.children[2..-1])))

        elsif method == :each_with_index
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

        elsif node.children[0..1] == [s(:send, nil, :loop), s(:args)]
          # input: loop {statements}
          # output: while(true) {statements}
          s(:while, s(:true), node.children[2])

        else
          super
        end
      end

      def on_class(node)
        name, inheritance, *body = node.children
        body.compact!

        if inheritance == s(:const, nil, :Exception)
          unless 
            body.any? {|statement| statement.type == :def and
            statement.children.first == :initialize}
          then
            body.unshift s(:def, :initialize, s(:args, s(:arg, :message)),
              s(:begin, s(:send, s(:self), :message=, s(:lvar, :message)),
              s(:send, s(:self), :name=, s(:sym, name.children[1])),
              s(:send, s(:self), :stack=, s(:send, s(:send, nil, :Error,
              s(:lvar, :message)), :stack))))
          end

          body = [s(:begin, *body)] if body.length > 1
          s(:class, name, s(:const, nil, :Error), *body)
        else
          super
        end
      end
    end

    DEFAULTS.push Functions
  end
end
