require 'ruby2js'

module Ruby2JS
  module Filter
    module Functions
      include SEXP

      # require explicit opt-in to to class => constructor mapping
      Filter.exclude :class

      VAR_TO_ASSIGN = {
        lvar: :lvasgn,
        ivar: :ivasgn,
        cvar: :cvasgn,
        gvar: :gvasgn
      }

      def on_send(node)
        target, method, *args = node.children
        return super if excluded?(method)

        if [:max, :min].include? method and args.length == 0
          return super unless node.is_method?
          process S(:send, s(:const, nil, :Math), node.children[1],
            s(:splat, target))

        elsif method == :call and target and target.type == :ivar
          process S(:send, s(:self), "_#{target.children.first.to_s[1..-1]}",
            *args)

        elsif method == :call and target and target.type == :cvar
          process S(:send, s(:attr, s(:self), :constructor), 
            "_#{target.children.first.to_s[2..-1]}", *args)

        elsif method == :keys and args.length == 0 and node.is_method?
          process S(:send, s(:const, nil, :Object), :keys, target)

        elsif method == :merge!
          if es2015
            process S(:send, s(:const, nil, :Object), :assign, target, *args)
          else
            copy = []

            unless
               target.type == :send and target.children.length == 2 and
               target.children[0] == nil
            then
               copy << s(:gvasgn, :$0, target)
               target = s(:gvar, :$0)
            end

            s(:send, s(:block, s(:send, nil, :lambda), s(:args),
              s(:begin, *copy, *args.map {|modname|
              s(:for, s(:lvasgn, :$_), modname,
              s(:send, target, :[]=,
              s(:lvar, :$_), s(:send, modname, :[], s(:lvar, :$_))))
              }, s(:return, target))), :[])
          end

        elsif method == :delete and args.length == 1
          if not target
            process S(:undef, args.first)
          elsif args.first.type == :str
            process S(:undef, S(:attr, target, args.first.children.first))
          else
            process S(:undef, S(:send, target, :[], args.first))
          end

        elsif method == :to_s
          process S(:call, target, :toString, *args)

        elsif method == :Array and target == nil
          if es2015
            process S(:send, s(:const, nil, :Array), :from, *args)
          else
            process S(:send, s(:attr, s(:attr, s(:const, nil, :Array), 
              :prototype), :slice), :call, *args)
          end

        elsif method == :to_i
          process node.updated :send, [nil, :parseInt, target, *args]

        elsif method == :to_f
          process node.updated :send, [nil, :parseFloat, target, *args]

        elsif method == :sub and args.length == 2
          process node.updated nil, [target, :replace, *args]

        elsif [:sub!, :gsub!].include? method
          method = :"#{method.to_s[0..-2]}"
          if VAR_TO_ASSIGN.keys.include? target.type
            process S(VAR_TO_ASSIGN[target.type], target.children[0], 
              S(:send, target, method, *node.children[2..-1]))
          elsif target.type == :send
            if target.children[0] == nil
              process S(:lvasgn, target.children[1], S(:send,
                S(:lvar, target.children[1]), method, *node.children[2..-1]))
            else
              process S(:send, target.children[0], :"#{target.children[1]}=", 
                S(:send, target, method, *node.children[2..-1]))
            end
          else
            super
          end

        elsif method == :scan and args.length == 1
          arg = args.first
          if arg.type == :str
            arg = arg.updated(:regexp,
              [s(:str, Regexp.escape(arg.children.first)), s(:regopt)])
          end

          pattern = arg.children.first.children.first
          pattern = pattern.gsub(/\\./, '').gsub(/\[.*\]/, '')

          if arg.type == :regexp
            gpattern = arg.updated(:regexp, [*arg.children[0...-1],
              s(:regopt, :g, *arg.children.last)])
          else
            super
          end
          
          if pattern.include? '('
            s(:block, s(:send,
              s(:send, process(target), :match, gpattern), :map),
              s(:args, s(:arg, :s)),
              s(:return, s(:send, s(:send, s(:lvar, :s), :match, arg),
              :slice, s(:int, 1))))
          else
            S(:send, process(target), :match, gpattern)
          end

        elsif method == :gsub and args.length == 2
          before, after = args
          if before.type == :regexp
            before = before.updated(:regexp, [*before.children[0...-1],
              s(:regopt, :g, *before.children.last)])
          elsif before.type == :str
            before = before.updated(:regexp,
              [s(:str, Regexp.escape(before.children.first)), s(:regopt, :g)])
          end
          process node.updated nil, [target, :replace, before, after]

        elsif method == :ord and args.length == 0
          if target.type == :str
            process S(:int, target.children.last.ord)
          else
            process S(:send, target, :charCodeAt, s(:int, 0))
          end

        elsif method == :chr and args.length == 0
          if target.type == :int
            process S(:str, target.children.last.chr)
          else
            process S(:send, s(:const, nil, :String), :fromCharCode, target)
          end

        elsif method == :empty? and args.length == 0
          process S(:send, S(:attr, target, :length), :==, s(:int, 0))

        elsif method == :nil? and args.length == 0
          process S(:send, target, :==, s(:nil))

        elsif [:start_with?, :end_with?].include? method and args.length == 1
          if es2015
	    if method == :start_with?
              process S(:send, target, :startsWith, *args)
            else
              process S(:send, target, :endsWith, *args)
            end
          else
	    if args.first.type == :str
	      length = S(:int, args.first.children.first.length)
	    else
	      length = S(:attr, *args, :length)
	    end

	    if method == :start_with?
	      process S(:send, S(:send, target, :substring, s(:int, 0), 
		length), :==, *args)
	    else
	      process S(:send, S(:send, target, :slice, 
		S(:send, length, :-@)), :==, *args)
	    end
          end

        elsif method == :clear and args.length == 0 and node.is_method?
          process S(:send, target, :length=, s(:int, 0))

        elsif method == :replace and args.length == 1
          process S(:begin, S(:send, target, :length=, s(:int, 0)),
             S(:send, target, :push, s(:splat, node.children[2])))

        elsif method == :include? and args.length == 1
          while target.type == :begin and target.children.length == 1
            target = target.children.first
          end

          if target.type == :irange
            S(:and, s(:send, args.first, :>=, target.children.first),
              s(:send, args.first, :<=, target.children.last))
          elsif target.type == :erange
            S(:and, s(:send, args.first, :>=, target.children.first),
              s(:send, args.first, :<, target.children.last))
          else
            process S(:send, S(:send, target, :indexOf, args.first), :!=,
              s(:int, -1))
          end

        elsif method == :respond_to? and args.length == 1
          process S(:in?, args.first, target)

        elsif method == :each
          process S(:send, target, :forEach, *args)

        elsif method == :downcase and args.length == 0
          process S(:send, target, :toLowerCase)

        elsif method == :upcase and args.length == 0
          process S(:send, target, :toUpperCase)

        elsif method == :strip and args.length == 0
          process S(:send, target, :trim)

        elsif node.children[0..1] == [nil, :puts]
          process S(:send, s(:attr, nil, :console), :log, *args)

        elsif method == :first
          if node.children.length == 2
            process S(:send, target, :[], s(:int, 0))
          elsif node.children.length == 3
            process on_send S(:send, target, :[], s(:erange,
              s(:int, 0), node.children[2]))
          else
            super
          end

        elsif method == :last
          if node.children.length == 2
            process on_send S(:send, target, :[], s(:int, -1))
          elsif node.children.length == 3
            process S(:send, target, :slice,
              s(:send, s(:attr, target, :length), :-, node.children[2]),
              s(:attr, target, :length))
          else
            super
          end


        elsif method == :[]
          # resolve negative literal indexes
          i = proc do |index|
            if index.type == :int and index.children.first < 0
              process S(:send, S(:attr, target, :length), :-, 
                s(:int, -index.children.first))
            else
              index
            end
          end

          index = args.first

          if not index
            super

          elsif index.type == :regexp
            process S(:send, 
              s(:or, S(:send, process(target), :match, index), s(:array)),
              :[], args[1] || s(:int, 0))

          elsif node.children.length != 3
            super

          elsif index.type == :int and index.children.first < 0
            process S(:send, target, :[], i.(index))

          elsif index.type == :erange
            start, finish = index.children
            process S(:send, target, :slice, i.(start), i.(finish))

          elsif index.type == :irange
            start, finish = index.children
            if finish.type == :int
              final = S(:int, finish.children.first+1)
            else
              final = S(:send, finish, :+, s(:int, 1))
            end

            # No need for the last argument if it's -1
            # This means take all to the end of array
            if finish.children.first == -1
              process S(:send, target, :slice, start)
            else
              process S(:send, target, :slice, start, final)
            end

          else
            super
          end

        elsif method == :reverse! and node.is_method? 
          # input: a.reverse!
          # output: a.splice(0, a.length, *a.reverse)
          process S(:send, target, :splice, s(:int, 0), 
            s(:attr, target, :length), s(:splat, S(:send, target, 
            :reverse, *node.children[2..-1])))

        elsif method == :each_with_index
          process S(:send, target, :forEach, *args)

        elsif method == :inspect and args.length == 0
          S(:send, s(:const, nil, :JSON), :stringify, process(target))

        elsif method == :* and target.type == :str
          process S(:send, s(:send, s(:const, nil, :Array), :new,
            s(:send, args.first, :+, s(:int, 1))), :join, target)

        elsif [:is_a?, :kind_of?].include? method and args.length == 1
          if args[0].type == :const
            parent = args[0].children.last
            parent = :Number if parent == :Float
            parent = :Object if parent == :Hash
            parent = :Function if parent == :Proc
            parent = :Error if parent == :Exception
            parent = :RegExp if parent == :Regexp
            if parent == :Array
              S(:send, s(:const, nil, :Array), :isArray, target)
            elsif [:Arguments, :Boolean, :Date, :Error, :Function, :Number,
                :Object, :RegExp, :String].include? parent
              S(:send, s(:send, s(:attr, s(:attr, s(:const, nil, Object), 
                :prototype), :toString), :call, target), :===,
                s(:str, "[object #{parent.to_s}]"))
            else
              super
            end
          else
            super
          end

        elsif target && target.type == :send and target.children[1] == :delete
          # prevent chained delete methods from being converted to undef
          S(:send, target.updated(:sendw), *node.children[1..-1])

        elsif es2017 and method==:entries and args.length==0 and node.is_method?
          process node.updated(nil, [s(:const, nil, :Object), :entries, target])

        elsif es2017 and method==:values and args.length==0 and node.is_method?
          process node.updated(nil, [s(:const, nil, :Object), :values, target])

        elsif es2017 and method==:rjust
          process node.updated(nil, [target, :padStart, *args])

        elsif es2017 and method==:ljust
          process node.updated(nil, [target, :padEnd, *args])

        elsif method == :class and args.length==0 and not node.is_method?
          process node.updated(:attr, [target, :constructor])

        else
          super
        end
      end

      def on_block(node)
        call = node.children.first
        method = call.children[1]
        return super if excluded?(method)

        if [:setInterval, :setTimeout].include? method
          return super unless call.children.first == nil
          block = process s(:block, s(:send, nil, :proc), *node.children[1..-1])
          on_send call.updated nil, [*call.children[0..1], block,
            *call.children[2..-1]]

        elsif [:sub, :gsub, :sub!, :gsub!, :sort!].include? method
          return super if call.children.first == nil
          block = s(:block, s(:send, nil, :proc), node.children[1],
            s(:autoreturn, *node.children[2..-1]))
          process call.updated(nil, [*call.children, block])

        elsif method == :select and call.children.length == 2
          call = call.updated nil, [call.children.first, :filter]
          node.updated nil, [process(call), process(node.children[1]),
            s(:autoreturn, *process_all(node.children[2..-1]))]

        elsif method == :any? and call.children.length == 2
          call = call.updated nil, [call.children.first, :some]
          node.updated nil, [process(call), process(node.children[1]),
            s(:autoreturn, *process_all(node.children[2..-1]))]

        elsif method == :all? and call.children.length == 2
          call = call.updated nil, [call.children.first, :every]
          node.updated nil, [process(call), process(node.children[1]),
            s(:autoreturn, *process_all(node.children[2..-1]))]

        elsif method == :find and call.children.length == 2
          node.updated nil, [process(call), process(node.children[1]),
            s(:autoreturn, *process_all(node.children[2..-1]))]

        elsif method == :find_index and call.children.length == 2
          call = call.updated nil, [call.children.first, :findIndex]
          node.updated nil, [process(call), process(node.children[1]),
            s(:autoreturn, *process_all(node.children[2..-1]))]

        elsif method == :map and call.children.length == 2
          node.updated nil, [process(call), process(node.children[1]),
            s(:autoreturn, *process_all(node.children[2..-1]))]

        elsif [:map!, :select!].include? method
          # input: a.map! {expression}
          # output: a.splice(0, a.length, *a.map {expression})
          method = (method == :map! ? :map : :select)
          target = call.children.first
          process call.updated(:send, [target, :splice, s(:splat, s(:send, 
            s(:array, s(:int, 0), s(:attr, target, :length)), :concat,
            s(:block, s(:send, target, method, *call.children[2..-1]),
            *node.children[1..-1])))])

        elsif node.children[0..1] == [s(:send, nil, :loop), s(:args)]
          # input: loop {statements}
          # output: while(true) {statements}
          S(:while, s(:true), node.children[2])

        elsif method == :delete
          # restore delete methods that are prematurely mapped to undef
          result = super

          if result.children[0].type == :undef
            call = result.children[0].children[0]
            if call.type == :attr
              call = call.updated(:send, 
                [call.children[0], :delete, s(:str, call.children[1])])
              result = result.updated(nil, [call, *result.children[1..-1]])
            else
              call = call.updated(nil, 
                [call.children[0], :delete, *call.children[2..-1]])
              result = result.updated(nil, [call, *result.children[1..-1]])
            end
          end

          result

        elsif method == :downto
          range = s(:irange, call.children[0], call.children[2])
          call = call.updated(nil, [s(:begin, range), :step, s(:int, -1)])
          process node.updated(nil, [call, *node.children[1..-1]])

        elsif method == :upto
          range = s(:irange, call.children[0], call.children[2])
          call = call.updated(nil, [s(:begin, range), :step, s(:int, 1)])
          process node.updated(nil, [call, *node.children[1..-1]])

        elsif 
          method == :each and call.children[0].type == :send and
          call.children[0].children[1] == :step
        then
          # i.step(j, n).each {|v| ...}
          range = call.children[0]
          step = range.children[3] || s(:int, 1)
          call = call.updated(nil, [s(:begin, 
            s(:irange, range.children[0], range.children[2])),
            :step, step])
          process node.updated(nil, [call, *node.children[1..-1]])

        elsif 
          # (a..b).each {|v| ...}
          method == :each and
          call.children[0].type == :begin and
          call.children[0].children.length == 1 and
          [:irange, :erange].include? call.children[0].children[0].type and
          node.children[1].children.length == 1
        then
          s(:for, s(:lvasgn, node.children[1].children[0].children[0]), 
            call.children[0].children[0], node.children[2])

        elsif 
          [:each, :each_value].include? method and 
          node.children[1].children.length == 1
        then
          if es2015
            process node.updated(:for_of, 
              [s(:lvasgn, node.children[1].children[0].children[0]),
              node.children[0].children[0], node.children[2]])
          else
            process node.updated(nil, [s(:send, call.children[0], 
              :forEach), *node.children[1..2]])
          end

        elsif 
          method == :each_key and 
          [:each, :each_key].include? method and 
          node.children[1].children.length == 1
        then
          process node.updated(:for, 
            [s(:lvasgn, node.children[1].children[0].children[0]),
            node.children[0].children[0], node.children[2]])

        elsif es2015 and method == :inject
          process node.updated(:send, [call.children[0], :reduce,
            s(:block, s(:send, nil, :lambda), *node.children[1..2]),
            *call.children[2..-1]])

        elsif es2017 and method == :each_pair
          process node.updated(nil, [s(:send, s(:send, s(:const, nil, :Object),
            :entries, call.children[0]), :forEach), s(:args, s(:mlhs,
            *node.children[1].children)), node.children[2]])

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
            body.unshift S(:def, :initialize, s(:args, s(:arg, :message)),
              s(:begin, S(:send, s(:self), :message=, s(:lvar, :message)),
              S(:send, s(:self), :name=, s(:sym, name.children[1])),
              S(:send, s(:self), :stack=, s(:send, s(:send, nil, :Error,
              s(:lvar, :message)), :stack))))
          end

          body = [s(:begin, *body)] if body.length > 1
          S(:class, name, s(:const, nil, :Error), *body)
        else
          super
        end
      end
    end

    DEFAULTS.push Functions
  end
end
