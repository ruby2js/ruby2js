require 'ruby2js'

require 'regexp_parser/scanner'

module Ruby2JS
  module Filter
    module Functions
      include SEXP

      # require explicit opt-in to call => direct invocation mapping
      # (JS uses Function.prototype.call() which would break)
      Filter.exclude :call

      # Methods that convert only when is_method? is true (parentheses present)
      # OR when explicitly included via include: option.
      REQUIRE_PARENS = %i[keys values entries index rindex clear reverse! max min]

      # Check if a REQUIRE_PARENS method should convert:
      # - Always convert if node.is_method? (has parentheses)
      # - Also convert if explicitly included via include: option
      def parens_or_included?(node, method)
        return true if node.is_method?
        # Check if method was explicitly included via include: option
        explicitly_included?(method)
      end

      # Check if a method was explicitly included via the include: or include_all: option
      def explicitly_included?(method)
        @options[:include_all] || @options[:include]&.include?(method)
      end

      VAR_TO_ASSIGN = {
        lvar: :lvasgn,
        ivar: :ivasgn,
        cvar: :cvasgn,
        gvar: :gvasgn
      }

      # Helper to replace local variable references in an AST node
      def replace_lvar(node, old_name, new_name)
        return node unless Ruby2JS.ast_node?(node)
        if node.type == :lvar && node.children.first == old_name
          node.updated(nil, [new_name])
        else
          node.updated(nil, node.children.map { |c| replace_lvar(c, old_name, new_name) })
        end
      end

      def initialize(*args)
        @jsx = false
        super
      end

      def on_csend(node)
        target, method, *args = node.children

        # Handle empty? specially for csend - we want obj?.length === 0
        # not obj.length?.==(0)
        if method == :empty? and args.length == 0 and not excluded?(method)
          return process S(:send, S(:csend, target, :length), :==, s(:int, 0))
        end

        # process csend (safe navigation) nodes the same as send nodes
        # so method names get converted (e.g., include? -> includes)
        # then restore the csend type if needed
        result = on_send(node)
        if result&.type == :send and node.type == :csend
          result = result.updated(:csend)
        elsif result&.type == :call and node.type == :csend
          # Handle &.call -> ccall (conditional call) for optional chaining
          result = result.updated(:ccall)
        end
        result
      end

      def on_send(node)
        target, method, *args = node.children
        return super if excluded?(method) and method != :call

        # Class.new { }.new -> object literal {}
        # Transform anonymous class instantiation to object literal
        if method == :new and target and target.type == :block
          block_call = target.children[0]
          if block_call.type == :send and
             block_call.children[0]&.type == :const and
             block_call.children[0].children == [nil, :Class] and
             block_call.children[1] == :new and
             block_call.children.length == 2  # no inheritance

            # Extract body from block
            body = target.children[2]
            body = body.children if body&.type == :begin
            body = [body].compact unless body.is_a?(Array)

            # Convert method definitions to hash pairs
            pairs = []
            body.each do |m|
              next unless m.type == :def
              name = m.children[0]
              method_args = m.children[1]
              method_body = m.children[2]

              if name.to_s.end_with?('=')
                # Setter: def foo=(v) -> prop with set
                base_name = name.to_s[0..-2].to_sym
                setter = s(:defm, nil, method_args, method_body)

                # Check if there's already a getter for this property
                existing = pairs.find { |p| p.children[0].type == :prop && p.children[0].children[0] == base_name }
                if existing
                  # Merge with existing getter
                  pairs.delete(existing)
                  pairs << s(:pair, s(:prop, base_name),
                    {get: existing.children[1][:get], set: setter})
                else
                  pairs << s(:pair, s(:prop, base_name), {set: setter})
                end
              elsif !m.is_method? and method_args.children.empty?
                # Getter: def foo (no parens, no args) -> prop with get
                getter = s(:defm, nil, method_args, s(:autoreturn, method_body))

                # Check if there's already a setter for this property
                existing = pairs.find { |p| p.children[0].type == :prop && p.children[0].children[0] == name }
                if existing
                  # Merge with existing setter
                  pairs.delete(existing)
                  pairs << s(:pair, s(:prop, name),
                    {get: getter, set: existing.children[1][:set]})
                else
                  pairs << s(:pair, s(:prop, name), {get: getter})
                end
              else
                # Regular method with args/parens -> shorthand method syntax
                pairs << s(:pair, s(:sym, name), s(:defm, nil, method_args, method_body))
              end
            end

            return process s(:hash, *pairs)
          end
        end

        # debugger as a standalone statement -> JS debugger statement
        if method == :debugger and target.nil? and args.empty?
          return s(:debugger)
        end

        # typeof(x) -> typeof x (JS type checking operator)
        if method == :typeof and target.nil? and args.length == 1
          return s(:typeof, process(args.first))
        end

        if [:max, :min].include? method and args.length == 0
          if target.type == :array
            process S(:send, s(:const, nil, :Math), node.children[1],
              *target.children)
          elsif parens_or_included?(node, method)
            process S(:send, s(:const, nil, :Math), node.children[1],
              s(:splat, target))
          else
            return super
          end

        elsif method == :call and target and 
          (%i[ivar cvar].include?(target.type) or not excluded?(:call))

          S(:call, process(target), nil, *process_all(args))

        elsif method == :keys and args.length == 0 and parens_or_included?(node, method)
          # hash.keys → Object.keys(hash)
          process S(:send, s(:const, nil, :Object), :keys, target)

        # define_method(name, block_var) inside a method body
        # -> this.constructor.prototype[name] = block_var
        elsif method == :define_method and target.nil? and args.length == 2
          process S(:send,
            s(:attr, s(:attr, s(:self), :constructor), :prototype),
            :[]=, args[0], args[1])

        elsif method == :[]= and args.length == 3 and
          args[0].type == :regexp and args[1].type == :int

          index = args[1].children.first

          # identify groups
          regex = args[0].children.first.children.first
          tokens = Regexp::Scanner.scan(regex)
          groups = []
          stack = []
          tokens.each do |token|
            next unless token[0] == :group
            if token[1] == :capture
              groups.push token.dup
              return super if groups.length == index and not stack.empty?
              stack.push groups.last
            elsif token[1] == :close
              stack.pop[-1]=token.last
            end
          end
          group = groups[index-1]

          # rewrite regex
          prepend = nil
          append = nil

          if group[4] < regex.length
            regex = (regex[0...group[4]] + '(' + regex[group[4]..-1] + ')').
              sub(/\$\)$/, ')$')
            append = 2
          end

          if group[4] - group[3] == 2
            regex = regex[0...group[3]] + regex[group[4]..-1]
            append = 1 if append
          end

          if group[3] > 0
            regex = ('(' + regex[0...group[3]] + ')' + regex[group[3]..-1]).
              sub(/^\(\^/, '^(')
            prepend = 1
            append += 1 if append
          end

          regex = process s(:regexp, s(:str, regex), args[0].children.last)

          # 
          if args.last.type == :str
            str = args.last.children.first.gsub('$', '$$')
            str = "$#{prepend}#{str}" if prepend
            str = "#{str}$#{append}" if append
            expr = s(:send, target, :replace, regex, s(:str, str))
          else
            dstr = args.last.type == :dstr ? args.last.children.dup : [args.last]
            if prepend
              dstr.unshift s(:send, s(:lvar, :match), :[], s(:int, prepend-1))
            end
            if append
              dstr << s(:send, s(:lvar, :match), :[], s(:int, append-1))
            end

            expr = s(:block,
              s(:send, target, :replace, regex),
              s(:args, s(:arg, :match)),
              process(s(:dstr, *dstr)))
          end

          if VAR_TO_ASSIGN.keys.include? target.type
            S(VAR_TO_ASSIGN[target.type], target.children.first, expr)
          elsif target.type == :send
            if target.children[0] == nil
              S(:lvasgn, target.children[1], expr)
            else
              S(:send, target.children[0], :"#{target.children[1]}=", expr)
            end
          else
            super
          end

        elsif method == :[]= and args.length == 2 and
          args[0].type == :int and args[0].children.first < 0
          # arr[-1] = x => arr[arr.length - 1] = x
          neg_index = -args[0].children.first
          new_index = S(:send, S(:attr, target, :length), :-, s(:int, neg_index))
          process S(:send, target, :[]=, new_index, args[1])

        elsif method == :[]= and args.length == 2 and
          %i[irange erange].include?(args[0].type)
          # input: arr[start..finish] = value or arr[start...finish] = value
          # output: arr.splice(start, length, ...value)
          range = args[0]
          value = args[1]
          start, finish = range.children

          if range.type == :erange
            # exclusive range: start...finish
            if finish
              len = S(:send, finish, :-, start)
            else
              # no finish means to end of array
              len = S(:send, s(:attr, target, :length), :-, start)
            end
          else
            # inclusive range: start..finish
            if finish&.type == :int && finish.children.first == -1
              # start..-1 means from start to end
              len = S(:send, s(:attr, target, :length), :-, start)
            elsif finish
              len = S(:send, S(:send, finish, :-, start), :+, s(:int, 1))
            else
              len = S(:send, s(:attr, target, :length), :-, start)
            end
          end

          # Spread the value if it's an array-like
          process S(:send, target, :splice, start, len, s(:splat, value))

        elsif method == :merge
          args.unshift target
          process S(:hash, *args.map {|arg| s(:kwsplat, arg)})

        elsif method == :merge!
          process S(:assign, target, *args)

        elsif method == :delete and args.length == 1
          if not target
            process S(:undef, args.first)
          elsif args.first.type == :str
            process S(:undef, S(:attr, target, args.first.children.first))
          else
            process S(:undef, S(:send, target, :[], args.first))
          end

        elsif method == :to_s
          if @options[:nullish_to_s] && es2020 && args.empty?
            # (x ?? '').toString() - nil-safe conversion matching Ruby's nil.to_s => ""
            process S(:call,
              s(:begin, s(:nullish, target, s(:str, ''))),
              :toString)
          else
            process S(:call, target, :toString, *args)
          end

        elsif method == :Array and target == nil
          process S(:send, s(:const, nil, :Array), :from, *args)

        elsif method == :String and target == nil and args.length == 1
          if @options[:nullish_to_s] && es2020
            # String(x ?? '') - nil-safe conversion matching Ruby's String(nil) => ""
            # Wrap the argument in nullish coalescing, then let the converter handle it
            node.updated(nil, [nil, :String,
              s(:begin, s(:nullish, process(args.first), s(:str, '')))])
          else
            super
          end

        elsif method == :to_i
          process node.updated :send, [nil, :parseInt, target, *args]

        elsif method == :to_f
          process node.updated :send, [nil, :parseFloat, target, *args]

        elsif method == :to_json
          process node.updated :send, [s(:const, nil, :JSON), :stringify, target, *args]

        elsif method == :sub and args.length == 2
          if args[1].type == :str
            args[1] = s(:str, args[1].children.first.gsub(/\\(\d)/, "$\\1"))
          end
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

          if arg.type == :regexp
            pattern = arg.children.first.children.first
            pattern = pattern.gsub(/\\./, '').gsub(/\[.*\]/, '')

            gpattern = arg.updated(:regexp, [*arg.children[0...-1],
              s(:regopt, :g, *arg.children.last)])
          else
            gpattern = s(:send, s(:const, nil, :RegExp), :new, arg, s(:str, 'g'))
          end

          if arg.type != :regexp or pattern.include? '('
            if es2020
              # Array.from(str.matchAll(/.../g), s => s.slice(1))
              s(:send, s(:const, nil, :Array), :from,
                s(:send, process(target), :matchAll, gpattern),
                s(:block, s(:send, nil, :proc), s(:args, s(:arg, :s)),
                  s(:send, s(:lvar, :s), :slice, s(:int, 1))))
            else
              # (str.match(/.../g) || []).map(s => s.match(/.../).slice(1))
              s(:block, s(:send,
                s(:or, s(:send, process(target), :match, gpattern), s(:array)),
                :map), s(:args, s(:arg, :s)),
                s(:return, s(:send, s(:send, s(:lvar, :s), :match, arg),
                :slice, s(:int, 1))))
            end
          else
            # str.match(/.../g)
            S(:send, process(target), :match, gpattern)
          end

        elsif method == :gsub and args.length == 2
          before, after = args
          if before.type == :regexp
            before = before.updated(:regexp, [*before.children[0...-1],
              s(:regopt, :g, *before.children.last)])
          elsif before.type == :str and not es2021
            before = before.updated(:regexp,
              [s(:str, Regexp.escape(before.children.first)), s(:regopt, :g)])
          end
          if after.type == :str
            after = s(:str, after.children.first.gsub(/\\(\d)/, "$\\1"))
          end

          if es2021
            process node.updated nil, [target, :replaceAll, before, after]
          else
            process node.updated nil, [target, :replace, before, after]
          end

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

        elsif method == :zero? and args.length == 0
          process S(:send, target, :===, s(:int, 0))

        elsif method == :positive? and args.length == 0
          process S(:send, target, :>, s(:int, 0))

        elsif method == :negative? and args.length == 0
          process S(:send, target, :<, s(:int, 0))

        elsif method == :any? and args.length == 0
          # arr.any? => arr.some(Boolean)
          process S(:send, target, :some, s(:const, nil, :Boolean))

        elsif method == :all? and args.length == 0
          # arr.all? => arr.every(Boolean)
          process S(:send, target, :every, s(:const, nil, :Boolean))

        elsif method == :none? and args.length == 0
          # arr.none? => !arr.some(Boolean)
          process S(:send, S(:send, target, :some, s(:const, nil, :Boolean)), :!)

        elsif [:start_with?, :end_with?].include? method and args.length == 1
          if method == :start_with?
            process S(:send, target, :startsWith, *args)
          else
            process S(:send, target, :endsWith, *args)
          end

        elsif method == :clear and args.length == 0 and parens_or_included?(node, method)
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
            process S(:send, target, :includes, args.first)
          end

        elsif method == :respond_to? and args.length == 1
          process S(:in?, args.first, target)

        elsif method == :send and args.length >= 1
          # target.send(:method, arg1, arg2) => target.method(arg1, arg2)
          # target.send(method_var, arg1) => target[method_var](arg1)
          method_name = args.first
          method_args = args[1..-1]
          if method_name.type == :sym
            # Static method name: target.send(:foo, x) => target.foo(x)
            process S(:send, target, method_name.children.first, *method_args)
          else
            # Dynamic method name: target.send(m, x) => target[m](x)
            process S(:send!, S(:send, target, :[], method_name), nil, *method_args)
          end

        elsif [:has_key?, :key?, :member?].include?(method) and args.length == 1
          # hash.has_key?(k) => k in hash
          process S(:in?, args.first, target)

        elsif method == :each
          process S(:send, target, :forEach, *args)

        elsif method == :downcase and args.length == 0
          process s(:send!, target, :toLowerCase)

        elsif method == :upcase and args.length == 0
          process s(:send!, target, :toUpperCase)

        elsif method == :strip and args.length == 0
          process s(:send!, target, :trim)

        elsif method == :join and args.length == 0
          # Ruby's join defaults to "", JS defaults to ","
          process node.updated(nil, [target, :join, s(:str, '')])

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
            if es2022
              process S(:send, target, :at, s(:int, -1))
            else
              process on_send S(:send, target, :[], s(:int, -1))
            end
          elsif node.children.length == 3
            process S(:send, target, :slice,
              s(:send, s(:attr, target, :length), :-, node.children[2]),
              s(:attr, target, :length))
          else
            super
          end


        elsif method == :[] and target == s(:const, nil, :Hash)
          s(:send, s(:const, nil, :Object), :fromEntries, *process_all(args))

        elsif target == s(:const, nil, :JSON)
          if method == :generate or method == :dump
            # JSON.generate(x) / JSON.dump(x) => JSON.stringify(x)
            process node.updated(nil, [target, :stringify, *args])
          elsif method == :parse or method == :load
            # JSON.parse(x) / JSON.load(x) => JSON.parse(x)
            super
          else
            super
          end

        elsif method == :[]
          # resolve negative literal indexes
          i = proc do |index|
            if index.type == :int and index.children.first < 0
              if es2022
                return process S(:send, target, :at, index)
              else
                process S(:send, S(:attr, target, :length), :-,
                  s(:int, -index.children.first))
              end
            else
              index
            end
          end

          index = args.first

          if not index
            super

          elsif index.type == :regexp
            if es2020
              process S(:csend,
                S(:send, process(target), :match, index),
                :[], args[1] || s(:int, 0))
            else
              process S(:send,
                s(:or, S(:send, process(target), :match, index), s(:array)),
                :[], args[1] || s(:int, 0))
            end

          elsif args.length == 2
            # str[start, length] => str.slice(start, start + length)
            # Ruby's 2-arg slice: str[start, length] extracts length chars starting at start
            start = args[0]
            length = args[1]
            if start.type == :int && start.children.first < 0
              # Handle negative start index (only for literal integers)
              start_expr = S(:send, S(:attr, target, :length), :-, s(:int, -start.children.first))
            else
              start_expr = start
            end
            end_expr = S(:send, start_expr, :+, length)
            process S(:send, target, :slice, start_expr, end_expr)

          elsif node.children.length != 3
            super

          elsif index.type == :int and index.children.first < 0
            process S(:send, target, :[], i.(index))

          elsif index.type == :erange
            start, finish = index.children
            if not finish
              process S(:send, target, :slice, start)
            elsif finish.type == :int
              process S(:send, target, :slice, i.(start), finish)
            else
              process S(:send, target, :slice, i.(start), i.(finish))
            end

          elsif index.type == :irange
            start, finish = index.children
            if finish and finish.type == :int
              final = S(:int, finish.children.first+1)
            else
              final = S(:send, finish, :+, s(:int, 1))
            end

            # No need for the last argument if it's -1
            # This means take all to the end of array
            if not finish or finish.children.first == -1
              process S(:send, target, :slice, start)
            else
              process S(:send, target, :slice, start, final)
            end

          else
            super
          end

        elsif method == :slice! and args.length == 1
          arg = args.first
          if arg.type == :irange
            # input: a.slice!(start..-1)
            # output: a.splice(start)
            start, finish = arg.children
            if finish&.type == :int && finish.children.first == -1
              process S(:send, target, :splice, process(start))
            else
              # input: a.slice!(start..finish)
              # output: a.splice(start, finish - start + 1)
              len = S(:send, S(:send, process(finish), :-, process(start)), :+, s(:int, 1))
              process S(:send, target, :splice, process(start), len)
            end
          elsif arg.type == :erange
            # input: a.slice!(start...finish)
            # output: a.splice(start, finish - start)
            start, finish = arg.children
            if finish
              len = S(:send, process(finish), :-, process(start))
              process S(:send, target, :splice, process(start), len)
            else
              process S(:send, target, :splice, process(start))
            end
          else
            # input: a.slice!(index) or a.slice!(start, length)
            # output: a.splice(index, 1) or a.splice(start, length)
            if args.length == 1
              process S(:send, target, :splice, process(arg), s(:int, 1))
            else
              process S(:send, target, :splice, *process_all(args))
            end
          end

        elsif method == :reverse! and parens_or_included?(node, method)
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
          process S(:send, target, :repeat, args.first)

        elsif method == :* and target.type == :array and args.length == 1
          # [a, b] * n => Array.from({length: n}, () => [a, b]).flat()
          # For single-element arrays: [a] * n => Array(n).fill(a)
          if target.children.length == 1
            # Single element: Array(n).fill(element)
            process S(:send, s(:send, s(:const, nil, :Array), nil, args.first),
              :fill, target.children.first)
          else
            # Multiple elements: Array.from({length: n}, () => [a, b]).flat()
            # Array.from with length object and mapper, then flatten
            # Use send! to force method call syntax (with parens)
            length_obj = s(:hash, s(:pair, s(:sym, :length), args.first))
            mapper = s(:block, s(:send, nil, :proc), s(:args), target)
            process S(:send!,
              s(:send, s(:const, nil, :Array), :from, length_obj, mapper),
              :flat)
          end

        elsif method == :+ and target.type == :array and args.length == 1 and args.first.type == :array
          # [a, b] + [c] => [...[a, b], ...[c]] or [a, b].concat([c])
          # Using concat for clarity
          process S(:send, target, :concat, args.first)

        elsif method == :+ and args.length == 1 and args.first.type == :array
          # expr + [c] where expr might be an array - use concat
          # This handles cases like Array(n).fill(x) + [y]
          process S(:send, target, :concat, args.first)

        elsif [:is_a?, :kind_of?].include? method and args.length == 1
          if args[0].type == :const
            parent = args[0].children.last
            if parent == :Array
              # Array.isArray(obj)
              S(:send, s(:const, nil, :Array), :isArray, target)
            elsif parent == :Integer
              # typeof obj === "number" && Number.isInteger(obj)
              S(:and,
                s(:send, s(:send, nil, :typeof, target), :===, s(:str, "number")),
                s(:send, s(:const, nil, :Number), :isInteger, target))
            elsif [:Float, :Numeric].include? parent
              # typeof obj === "number"
              S(:send, s(:send, nil, :typeof, target), :===, s(:str, "number"))
            elsif parent == :String
              # typeof obj === "string"
              S(:send, s(:send, nil, :typeof, target), :===, s(:str, "string"))
            elsif parent == :Symbol
              # typeof obj === "symbol"
              S(:send, s(:send, nil, :typeof, target), :===, s(:str, "symbol"))
            elsif parent == :Hash
              # typeof obj === "object" && obj !== null && !Array.isArray(obj)
              S(:and,
                s(:and,
                  s(:send, s(:send, nil, :typeof, target), :===, s(:str, "object")),
                  s(:send, target, :'!==', s(:nil))),
                s(:send, s(:send, s(:const, nil, :Array), :isArray, target), :'!'))
            elsif parent == :NilClass
              # obj === null || obj === undefined
              S(:or,
                s(:send, target, :===, s(:nil)),
                s(:send, target, :===, s(:send, nil, :undefined)))
            elsif parent == :TrueClass
              # obj === true
              S(:send, target, :===, s(:true))
            elsif parent == :FalseClass
              # obj === false
              S(:send, target, :===, s(:false))
            elsif parent == :Boolean
              # typeof obj === "boolean"
              S(:send, s(:send, nil, :typeof, target), :===, s(:str, "boolean"))
            elsif parent == :Proc || parent == :Function
              # typeof obj === "function"
              S(:send, s(:send, nil, :typeof, target), :===, s(:str, "function"))
            elsif parent == :Regexp
              # obj instanceof RegExp
              S(:instanceof, target, s(:const, nil, :RegExp))
            elsif parent == :Exception || parent == :Error
              # obj instanceof Error
              S(:instanceof, target, s(:const, nil, :Error))
            else
              # User-defined classes: obj instanceof ClassName
              S(:instanceof, target, args[0])
            end
          else
            super
          end

        elsif method == :instance_of? and args.length == 1
          # instance_of? checks exact class (not subclasses)
          # obj.instance_of?(Foo) => obj.constructor === Foo
          if args[0].type == :const
            parent = args[0].children.last
            if parent == :Array
              # For Array, check constructor directly
              S(:send, s(:attr, target, :constructor), :===, s(:const, nil, :Array))
            elsif parent == :Integer
              # typeof + isInteger + not float
              S(:and,
                s(:and,
                  s(:send, s(:send, nil, :typeof, target), :===, s(:str, "number")),
                  s(:send, s(:const, nil, :Number), :isInteger, target)),
                s(:send, s(:send, target, :%, s(:int, 1)), :===, s(:int, 0)))
            elsif [:Float, :Numeric].include? parent
              # For Float, check it's a number but NOT an integer
              S(:and,
                s(:send, s(:send, nil, :typeof, target), :===, s(:str, "number")),
                s(:send, s(:send, s(:const, nil, :Number), :isInteger, target), :'!'))
            elsif parent == :String
              S(:send, s(:send, nil, :typeof, target), :===, s(:str, "string"))
            elsif parent == :Symbol
              S(:send, s(:send, nil, :typeof, target), :===, s(:str, "symbol"))
            elsif parent == :Hash
              # Check it's a plain object (constructor === Object)
              S(:send, s(:attr, target, :constructor), :===, s(:const, nil, :Object))
            elsif parent == :NilClass
              S(:or,
                s(:send, target, :===, s(:nil)),
                s(:send, target, :===, s(:send, nil, :undefined)))
            elsif parent == :TrueClass
              S(:send, target, :===, s(:true))
            elsif parent == :FalseClass
              S(:send, target, :===, s(:false))
            elsif parent == :Boolean
              S(:send, s(:send, nil, :typeof, target), :===, s(:str, "boolean"))
            elsif parent == :Proc || parent == :Function
              S(:send, s(:send, nil, :typeof, target), :===, s(:str, "function"))
            elsif parent == :Regexp
              S(:send, s(:attr, target, :constructor), :===, s(:const, nil, :RegExp))
            elsif parent == :Exception || parent == :Error
              S(:send, s(:attr, target, :constructor), :===, s(:const, nil, :Error))
            else
              # User-defined classes: obj.constructor === ClassName
              S(:send, s(:attr, target, :constructor), :===, args[0])
            end
          else
            super
          end

        elsif target && target.type == :send and target.children[1] == :delete
          # prevent chained delete methods from being converted to undef
          S(:send, target.updated(:sendw), *node.children[1..-1])

        elsif method==:entries and args.length==0 and parens_or_included?(node, method)
          process node.updated(nil, [s(:const, nil, :Object), :entries, target])

        elsif method==:values and args.length==0 and parens_or_included?(node, method)
          process node.updated(nil, [s(:const, nil, :Object), :values, target])

        elsif method==:rjust
          process node.updated(nil, [target, :padStart, *args])

        elsif method==:ljust
          process node.updated(nil, [target, :padEnd, *args])

        elsif method==:flatten and args.length == 0
          process node.updated(nil, [target, :flat, s(:lvar, :Infinity)])

        elsif method==:compact and args.length == 0
          # array.compact -> array.filter(x => x != null)
          # This removes nil/null values from the array (non-mutating)
          process s(:send, target, :filter,
            s(:block, s(:send, nil, :proc), s(:args, s(:arg, :x)),
              s(:send, s(:lvar, :x), :'!=', s(:nil))))

        elsif method==:compact! and args.length == 0
          # array.compact! -> array.splice(0, array.length, ...array.filter(x => x != null))
          # This mutates the array in place, removing nil/null values
          process s(:send, target, :splice,
            s(:int, 0),
            s(:attr, target, :length),
            s(:splat, s(:send, target, :filter,
              s(:block, s(:send, nil, :proc), s(:args, s(:arg, :x)),
                s(:send, s(:lvar, :x), :'!=', s(:nil))))))

        elsif method==:to_h and args.length==0
          process node.updated(nil, [s(:const, nil, :Object), :fromEntries,
            target])

        elsif method==:rstrip
          process node.updated(nil, [target, :trimEnd, *args])

        elsif method==:lstrip and args.length == 0
          process s(:send!, target, :trimStart)

        elsif method == :index and parens_or_included?(node, method)
          process node.updated(nil, [target, :indexOf, *args])

        elsif method == :rindex and parens_or_included?(node, method) and
            args.none? { |arg| arg.type == :block_pass }
          # Only convert to lastIndexOf when no block - with block, keep rindex
          process node.updated(nil, [target, :lastIndexOf, *args])

        elsif method == :class and args.length==0 and not node.is_method?
          process node.updated(:attr, [target, :constructor])

        elsif method == :superclass and args.length==0 and target&.type == :const and not node.is_method?
          # Foo.superclass => Object.getPrototypeOf(Foo.prototype).constructor
          # Only applies to constants (class names), not to variables like node.superclass
          process S(:attr,
            s(:send, s(:const, nil, :Object), :getPrototypeOf,
              s(:attr, target, :prototype)),
            :constructor)

        elsif method == :new and target == s(:const, nil, :Exception)
          process S(:send, s(:const, nil, :Error), :new, *args)

        elsif method == :escape and target == s(:const, nil, :Regexp) and es2025
          # Regexp.escape(str) => RegExp.escape(str) for ES2025+
          # (polyfill filter handles pre-ES2025 with polyfill)
          process S(:send, s(:const, nil, :RegExp), :escape, *args)

        elsif method == :block_given? and target == nil and args.length == 0
          process process s(:lvar, "_implicitBlockYield")

        elsif method == :abs and args.length == 0
          process S(:send, s(:const, nil, :Math), :abs, target)

        elsif method == :round and args.length == 0
          process S(:send, s(:const, nil, :Math), :round, target)

        elsif method == :ceil and args.length == 0
          process S(:send, s(:const, nil, :Math), :ceil, target)

        elsif method == :floor and args.length == 0
          process S(:send, s(:const, nil, :Math), :floor, target)

        elsif method == :rand and target == nil
          if args.length == 0
            process S(:send!, s(:const, nil, :Math), :random)
          elsif %i[irange erange].include? args.first.type
            range = args.first
            multiplier = s(:send, range.children.last, :-, range.children.first)
            if range.children.all? {|child| child.type == :int}
              multiplier = s(:int, range.children.last.children.last - range.children.first.children.last)
              multiplier = s(:int, multiplier.children.first + 1) if range.type == :irange
            elsif range.type == :irange
              if multiplier.children.last.type == :int
                diff = multiplier.children.last.children.last - 1
                multiplier = s(:send, *multiplier.children[0..1], s(:int, diff))
                multiplier = multiplier.children.first if diff == 0
                multiplier = s(:send, multiplier.children[0], :+, s(:int, -diff)) if diff < 0
              else
                multiplier = s(:send, multiplier, :+, s(:int, 1))
              end
            end
            raw = s(:send, s(:send, s(:const, nil, :Math), :random), :*, multiplier)
            if range.children.first != s(:int, 0)
              raw = s(:send, raw, :+, range.children.first)
            end
            process S(:send, nil, :parseInt, raw)
          else
            process S(:send, nil, :parseInt,
              s(:send, s(:send, s(:const, nil, :Math), :random),
              :*, args.first))
          end

        elsif method == :sum and args.length == 0
          process S(:send, target, :reduce, s(:block, s(:send, nil, :proc),
            s(:args, s(:arg, :a), s(:arg, :b)),
            s(:send, s(:lvar, :a), :+, s(:lvar, :b))), s(:int, 0))

        elsif [:reduce, :inject].include?(method) and args.length == 1 and args[0].type == :sym
          # reduce(:+) → reduce((a, b) => a + b)
          # reduce(:merge) → reduce((a, b) => ({...a, ...b}))
          op = args[0].children[0]
          if op == :merge
            # Hash merge: spread both objects
            process S(:send, target, :reduce, s(:block, s(:send, nil, :proc),
              s(:args, s(:arg, :a), s(:arg, :b)),
              s(:hash, s(:kwsplat, s(:lvar, :a)), s(:kwsplat, s(:lvar, :b)))))
          else
            # Arithmetic/other operators: a.op(b) or a op b
            process S(:send, target, :reduce, s(:block, s(:send, nil, :proc),
              s(:args, s(:arg, :a), s(:arg, :b)),
              s(:send, s(:lvar, :a), op, s(:lvar, :b))))
          end

        elsif method == :method_defined? and args.length >= 1
          if args[1] == s(:false)
            process S(:send, s(:attr, target, :prototype), :hasOwnProperty, args[0])
          elsif args.length == 1 or args[1] == s(:true)
            process S(:in?, args[0], s(:attr, target, :prototype))
          else
            process S(:if, args[1], s(:in?, args[0], s(:attr, target, :prototype)),
              s(:send, s(:attr, target, :prototype), :hasOwnProperty, args[0]))
          end

        elsif method == :alias_method and args.length == 2
          process S(:send, s(:attr, target, :prototype), :[]=, args[0],
            s(:attr, s(:attr, target, :prototype), args[1].children[0]))

        elsif method == :new and args.length == 2 and target == s(:const, nil, :Array)
          s(:send, S(:send, target, :new, args.first), :fill, args.last)

        elsif method == :freeze and args.length == 0
          # .freeze → Object.freeze(target), bare freeze → Object.freeze(this)
          process S(:send, s(:const, nil, :Object), :freeze, target || s(:self))

        elsif method == :to_sym and args.length == 0
          # .to_sym is a no-op - symbols are strings in JS
          process target

        elsif method == :reject and args.length == 1 and args[0]&.type == :block_pass
          # .reject(&:method) → .filter with negated block
          # reject(&:empty?) → filter(item => !item.empty())
          block_pass = args[0]
          if block_pass.children[0]&.type == :sym
            method_sym = block_pass.children[0].children[0]
            arg = s(:arg, :item)
            body = s(:send, s(:begin, s(:send, s(:lvar, :item), method_sym)), :!)
            new_block = s(:block, s(:send, target, :filter), s(:args, arg), s(:autoreturn, body))
            return process new_block
          end
          super

        elsif method == :chars and args.length == 0
          S(:send, s(:const, nil, :Array), :from, target)

        elsif method == :method and target == nil and args.length == 1
          # method(:name) => this.name.bind(this) or this[name].bind(this)
          name_arg = args.first
          if name_arg.type == :sym
            # method(:foo) => this.foo.bind(this)
            process S(:send, s(:attr, s(:self), name_arg.children.first), :bind, s(:self))
          else
            # method(name) => this[name].bind(this)
            process S(:send, s(:send, s(:self), :[], name_arg), :bind, s(:self))
          end

        else
          super
        end
      end

      def on_block(node)
        call = node.children.first
        method = call.children[1]
        return super if excluded?(method)

        if [:setInterval, :setTimeout, :set_interval, :set_timeout].include? method
          return super unless call.children.first == nil
          block = process s(:block, s(:send, nil, :proc), *node.children[1..-1])
          on_send call.updated nil, [*call.children[0..1], block,
            *call.children[2..-1]]

        elsif [:sub, :gsub, :sub!, :gsub!, :sort!].include? method
          return super if call.children.first == nil
          block = s(:block, s(:send, nil, :proc), node.children[1],
            s(:autoreturn, *node.children[2..-1]))
          process call.updated(nil, [*call.children, block])

        elsif method == :compact and call.children.length == 2
          # compact with a block is NOT the array compact method
          # (e.g., serializer.compact { ... } should not become filter)
          # Skip on_send processing by constructing the call node directly
          target = call.children.first
          processed_call = call.updated(nil, [process(target), :compact])
          node.updated nil, [processed_call, process(node.children[1]),
            *process_all(node.children[2..-1])]

        elsif method == :select and call.children.length == 2
          call = call.updated nil, [call.children.first, :filter]
          node.updated nil, [process(call), process(node.children[1]),
            s(:autoreturn, *process_all(node.children[2..-1]))]

        elsif method == :reject and call.children.length == 2
          # arr.reject { |x| cond } => arr.filter(x => !(cond))
          call = call.updated nil, [call.children.first, :filter]
          # Process the body first, then negate - use :send with :! to wrap
          processed_body = process_all(node.children[2..-1])
          negated_body = s(:send, s(:begin, *processed_body), :!)
          node.updated nil, [process(call), process(node.children[1]),
            s(:autoreturn, negated_body)]

        elsif method == :any? and call.children.length == 2
          call = call.updated nil, [call.children.first, :some]
          node.updated nil, [process(call), process(node.children[1]),
            s(:autoreturn, *process_all(node.children[2..-1]))]

        elsif method == :all? and call.children.length == 2
          call = call.updated nil, [call.children.first, :every]
          node.updated nil, [process(call), process(node.children[1]),
            s(:autoreturn, *process_all(node.children[2..-1]))]

        elsif method == :none? and call.children.length == 2
          # arr.none? { |x| cond } => !arr.some(x => cond)
          call = call.updated nil, [call.children.first, :some]
          some_result = node.updated nil, [process(call), process(node.children[1]),
            s(:autoreturn, *process_all(node.children[2..-1]))]
          s(:send, some_result, :!)

        elsif method == :find and call.children.length == 2
          node.updated nil, [process(call), process(node.children[1]),
            s(:autoreturn, *process_all(node.children[2..-1]))]

        elsif method == :flat_map and call.children.length == 2
          # Ruby's flat_map → JavaScript's flatMap
          call = call.updated nil, [call.children.first, :flatMap]
          node.updated nil, [process(call), process(node.children[1]),
            s(:autoreturn, *process_all(node.children[2..-1]))]

        elsif method == :group_by and call.children.length == 2
          # array.group_by { |x| x.category }
          # array.group_by { |k, v| k.to_s }  # with destructuring
          target = call.children.first
          args = node.children[1]
          block_body = node.children[2]

          # Check if we have multiple args (destructuring case)
          if args.children.length > 1
            # Multiple args: use destructuring and push the whole item as array
            arg_names = args.children.map { |arg| arg.children.first }
            # Create mlhs for destructuring: ([a, b]) => ...
            mlhs_arg = s(:mlhs, *args.children)
            # Push the reconstructed array [a, b]
            item_to_push = s(:array, *arg_names.map { |name| s(:lvar, name) })
            reduce_arg = s(:args, s(:arg, :$acc), mlhs_arg)
          else
            # Single arg: simple case
            arg_name = args.children.first.children.first
            item_to_push = s(:lvar, arg_name)
            reduce_arg = s(:args, s(:arg, :$acc), s(:arg, arg_name))
          end

          if es2024
            # ES2024+: Object.groupBy(array, x => x.category)
            # For destructuring, wrap args in mlhs: ([a, b]) => ...
            callback_args = if args.children.length > 1
              s(:args, s(:mlhs, *args.children))
            else
              node.children[1]
            end
            callback = s(:block, s(:send, nil, :proc), callback_args,
              s(:autoreturn, *node.children[2..-1]))
            process s(:send, s(:const, nil, :Object), :groupBy, target, callback)
          else
            # Pre-ES2024: array.reduce((acc, x) => { const key = ...; (acc[key] = acc[key] || []).push(x); return acc }, {})
            # Build: (acc[key] = acc[key] || []).push(item)
            acc_key = s(:send, s(:lvar, :$acc), :[], s(:lvar, :$key))
            acc_key_or_empty = s(:or, acc_key, s(:array))
            assign_and_push = s(:send,
              s(:send, s(:lvar, :$acc), :[]=, s(:lvar, :$key), acc_key_or_empty),
              :push, item_to_push)

            # Build the reduce block body
            reduce_body = s(:begin,
              s(:lvasgn, :$key, block_body),
              assign_and_push,
              s(:return, s(:lvar, :$acc)))

            reduce_block = s(:block,
              s(:send, nil, :proc),
              reduce_arg,
              reduce_body)

            process s(:send, target, :reduce, reduce_block, s(:hash))
          end

        elsif method == :sort_by and call.children.length == 2
          # array.sort_by { |x| x.name } => array.slice().sort((a, b) => ...)
          # With ES2023+: array.toSorted((a, b) => ...)
          target = call.children.first
          args = node.children[1]
          block_body = node.children[2]

          # Create two argument names for the comparison function
          arg_name = args.children.first.children.first
          arg_a = :"#{arg_name}_a"
          arg_b = :"#{arg_name}_b"

          # Replace references to the block argument with arg_a and arg_b
          key_a = replace_lvar(block_body, arg_name, arg_a)
          key_b = replace_lvar(block_body, arg_name, arg_b)

          # Build comparison: key_a < key_b ? -1 : key_a > key_b ? 1 : 0
          comparison = s(:if,
            s(:send, key_a, :<, key_b),
            s(:int, -1),
            s(:if,
              s(:send, key_a, :>, key_b),
              s(:int, 1),
              s(:int, 0)))

          compare_block = s(:block,
            s(:send, nil, :proc),
            s(:args, s(:arg, arg_a), s(:arg, arg_b)),
            s(:autoreturn, comparison))

          if es2023
            # Use toSorted for ES2023+
            process s(:send, target, :toSorted, compare_block)
          else
            # Use slice().sort() for older versions
            # Use :send! for slice to force method call output
            process s(:send, s(:send!, target, :slice), :sort, compare_block)
          end

        elsif method == :max_by and call.children.length == 2
          # array.max_by { |x| x.score } => array.reduce((a, b) => key(a) > key(b) ? a : b)
          target = call.children.first
          args = node.children[1]
          block_body = node.children[2]

          arg_name = args.children.first.children.first
          key_a = replace_lvar(block_body, arg_name, :a)
          key_b = replace_lvar(block_body, arg_name, :b)

          # Build: a, b => key(a) >= key(b) ? a : b
          comparison = s(:if, s(:send, key_a, :>=, key_b), s(:lvar, :a), s(:lvar, :b))

          reduce_block = s(:block,
            s(:send, nil, :proc),
            s(:args, s(:arg, :a), s(:arg, :b)),
            s(:autoreturn, comparison))

          process s(:send, target, :reduce, reduce_block)

        elsif method == :min_by and call.children.length == 2
          # array.min_by { |x| x.score } => array.reduce((a, b) => key(a) <= key(b) ? a : b)
          target = call.children.first
          args = node.children[1]
          block_body = node.children[2]

          arg_name = args.children.first.children.first
          key_a = replace_lvar(block_body, arg_name, :a)
          key_b = replace_lvar(block_body, arg_name, :b)

          # Build: a, b => key(a) <= key(b) ? a : b
          comparison = s(:if, s(:send, key_a, :<=, key_b), s(:lvar, :a), s(:lvar, :b))

          reduce_block = s(:block,
            s(:send, nil, :proc),
            s(:args, s(:arg, :a), s(:arg, :b)),
            s(:autoreturn, comparison))

          process s(:send, target, :reduce, reduce_block)

        elsif method == :find_index and call.children.length == 2
          call = call.updated nil, [call.children.first, :findIndex]
          node.updated nil, [process(call), process(node.children[1]),
            s(:autoreturn, *process_all(node.children[2..-1]))]

        elsif method == :index and call.children.length == 2
            call = call.updated nil, [call.children.first, :findIndex]
            node.updated nil, [process(call), process(node.children[1]),
              s(:autoreturn, *process_all(node.children[2..-1]))]

        elsif \
          # (a..b).map { |i| ... }
          method == :map and
          call.children[0].type == :begin and
          call.children[0].children.length == 1 and
          [:irange, :erange].include?(call.children[0].children[0].type) and
          node.children[1].children.length == 1
        then
          range = call.children[0].children[0]
          start_node = range.children[0]
          end_node = range.children[1]
          arg_name = node.children[1].children[0].children[0]
          block_body = node.children[2]

          # Calculate length: end - start + 1 for irange, end - start for erange
          if start_node.type == :int && start_node.children[0] == 0
            # (0..n) or (0...n) - length is just end+1 or end
            length = range.type == :irange ?
              s(:send, end_node, :+, s(:int, 1)) :
              end_node
          elsif start_node.type == :int && end_node.type == :int
            # Both are literals - compute length
            len_val = end_node.children[0] - start_node.children[0]
            len_val += 1 if range.type == :irange
            length = s(:int, len_val)
          elsif start_node.type == :int && start_node.children[0] == 1 && range.type == :irange
            # (1..n) - length is just n
            length = end_node
          else
            # General case: end - start + 1 (irange) or end - start (erange)
            length = s(:send, end_node, :-, start_node)
            length = s(:send, length, :+, s(:int, 1)) if range.type == :irange
          end

          # If starting from 0, use simpler form: Array.from({length}, (_, i) => ...)
          if start_node.type == :int && start_node.children[0] == 0
            callback = s(:block, s(:send, nil, :proc),
              s(:args, s(:arg, :_), s(:arg, arg_name)),
              s(:autoreturn, block_body))
            process s(:send, s(:const, nil, :Array), :from,
              s(:hash, s(:pair, s(:sym, :length), length)),
              callback)
          else
            # General case: need to offset the index
            # Array.from({length}, (_, $i) => { let i = $i + start; return ... })
            temp_var = :"$#{arg_name}"
            callback_body = s(:begin,
              s(:lvasgn, arg_name, s(:send, s(:lvar, temp_var), :+, start_node)),
              s(:autoreturn, block_body))
            callback = s(:block, s(:send, nil, :proc),
              s(:args, s(:arg, :_), s(:arg, temp_var)),
              callback_body)
            process s(:send, s(:const, nil, :Array), :from,
              s(:hash, s(:pair, s(:sym, :length), length)),
              callback)
          end

        elsif method == :map and call.children.length == 2
          # For destructuring (multiple args), wrap in mlhs: ([a, b]) => ...
          args = node.children[1]
          processed_args = if args.children.length > 1
            s(:args, s(:mlhs, *args.children))
          else
            process(args)
          end
          node.updated nil, [process(call), processed_args,
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
          S(:while, s(:true), process(node.children[2]))

        elsif method == :times and call.children.length == 2
          # input: n.times { |i| ... }
          # output: for (let i = 0; i < n; i++) { ... }
          count = call.children[0]

          # If no block variable provided, create a dummy one
          if node.children[1].children.empty?
            args = s(:args, s(:arg, :_))
          else
            args = node.children[1]
          end

          # Convert to range iteration: (0...n).each { |var| body }
          process node.updated(nil, [
            s(:send, s(:begin, s(:erange, s(:int, 0), count)), :each),
            args,
            node.children[2]
          ])

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

        elsif \
          method == :step and
          call.children[0].type == :begin and
          call.children[0].children.length == 1 and
          [:irange, :erange].include?(call.children[0].children[0].type) and
          node.children[1].children.length == 1
        then
          # (a..b).step(n) {|v| ...}
          range = call.children[0].children[0]
          step = call.children[2] || s(:int, 1)
          process s(:for, s(:lvasgn, node.children[1].children[0].children[0]),
            s(:send, range, :step, step), node.children[2])

        elsif \
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

        elsif \
          # (a..b).each {|v| ...}
          method == :each and
          call.children[0].type == :begin and
          call.children[0].children.length == 1 and
          [:irange, :erange].include? call.children[0].children[0].type and
          node.children[1].children.length == 1
        then
          process s(:for, s(:lvasgn, node.children[1].children[0].children[0]),
            call.children[0].children[0], node.children[2])

        elsif \
          [:each, :each_value].include? method
        then
          if node.children[1].children.length > 1
            process node.updated(:for_of,
              [s(:mlhs, *node.children[1].children.map {|child|
                s(:lvasgn, child.children[0])}),
              node.children[0].children[0], node.children[2]])
          elsif node.children[1].children[0].type == :mlhs
            process node.updated(:for_of,
              [s(:mlhs, *node.children[1].children[0].children.map {|child|
                s(:lvasgn, child.children[0])}),
              node.children[0].children[0], node.children[2]])
          else
            process node.updated(:for_of,
              [s(:lvasgn, node.children[1].children[0].children[0]),
              node.children[0].children[0], node.children[2]])
          end

        elsif \
          method == :each_key and
          [:each, :each_key].include? method and
          node.children[1].children.length == 1
        then
          process node.updated(:for,
            [s(:lvasgn, node.children[1].children[0].children[0]),
            node.children[0].children[0], node.children[2]])

        elsif method == :inject
          process node.updated(:send, [call.children[0], :reduce,
            s(:block, s(:send, nil, :lambda), *node.children[1..2]),
            *call.children[2..-1]])

        elsif method == :each_pair and node.children[1].children.length == 2
          # Object.entries(a).forEach(([key, value]) => {})
          process node.updated(nil, [s(:send, s(:send,
          s(:const, nil, :Object), :entries, call.children[0]), :each),
          node.children[1], node.children[2]])

        elsif method == :scan and call.children.length == 3
          process call.updated(nil, [*call.children, s(:block,
            s(:send, nil, :proc), *node.children[1..-1])])

        elsif method == :yield_self and call.children.length == 2
          process node.updated(:send, [s(:block, s(:send, nil, :proc),
            node.children[1], s(:autoreturn, node.children[2])),
            :[], call.children[0]])

        elsif method == :tap and call.children.length == 2
          process node.updated(:send, [s(:block, s(:send, nil, :proc),
            node.children[1], s(:begin, node.children[2],
            s(:return, s(:lvar, node.children[1].children[0].children[0])))),
            :[], call.children[0]])

        elsif method == :define_method and call.children.length == 3 and call.children[0]
          # Requires explicit receiver (receiver is added by on_class for calls without one)
          process node.updated(:send, [s(:attr, call.children[0], :prototype), :[]=,
            call.children[2], s(:deff, nil, *node.children[1..-1])])

        elsif method == :each_with_index and call.children.length == 2
          # array.each_with_index { |item, i| ... } => array.forEach((item, i) => ...)
          call = call.updated(nil, [call.children.first, :forEach])
          node.updated(nil, [process(call), *node.children[1..-1].map { |c| process(c) }])

        else
          super
        end
      end

      # Recursively add class name as receiver to define_method and method_defined? calls
      # This handles define_method/method_defined? inside loops like:
      #   %i[a b].each { |t| define_method(t) { ... } unless method_defined?(t) }
      def add_class_receiver(node, class_name)
        return node unless ast_node?(node)

        if node.type == :block
          call = node.children.first
          if call.type == :send and call.children[0..1] == [nil, :define_method]
            new_call = call.updated(:send, [class_name, *call.children[1..-1]])
            return node.updated(:block, [new_call, *node.children[1..-1].map { |c| add_class_receiver(c, class_name) }])
          end
        elsif node.type == :send and node.children[0..1] == [nil, :method_defined?]
          return node.updated(:send, [class_name, *node.children[1..-1]])
        end

        # Recursively process children
        new_children = node.children.map do |child|
          if ast_node?(child)
            add_class_receiver(child, class_name)
          else
            child
          end
        end

        if new_children != node.children
          node.updated(nil, new_children)
        else
          node
        end
      end

      def on_class(node)
        name, inheritance, *body = node.children
        body.compact!

        body.each_with_index do |child, i|
          # alias_method without receiver -> add class name as receiver
          if child.type == :send and child.children[0..1] == [nil, :alias_method]
            body[i] = child.updated(:send, [name, *child.children[1..-1]])
          # method_defined? without receiver -> add class name as receiver
          elsif child.type == :send and child.children[0..1] == [nil, :method_defined?]
            body[i] = child.updated(:send, [name, *child.children[1..-1]])
          # define_method without receiver -> add class name as receiver
          elsif child.type == :block
            call = child.children.first
            if call.type == :send and call.children[0..1] == [nil, :define_method]
              new_call = call.updated(:send, [name, *call.children[1..-1]])
              body[i] = child.updated(:block, [new_call, *child.children[1..-1]])
            else
              # Recursively search for define_method/method_defined? inside nested blocks (e.g., .each loops)
              body[i] = add_class_receiver(child, name)
            end
          elsif child.type == :begin
            # Process children of begin node (class body wrapped in begin)
            body[i] = add_class_receiver(child, name)
          end
        end

        if inheritance == s(:const, nil, :Exception)
          unless
            body.any? {|statement| statement.type == :def and
            statement.children.first == :initialize}
          then
            body.unshift s(:def, :initialize, s(:args, s(:arg, :message)),
              s(:begin, s(:send, s(:self), :message=, s(:lvar, :message)),
              s(:send, s(:self), :name=, s(:sym, name.children[1])),
              s(:send, s(:self), :stack=, s(:attr, s(:send, nil, :Error,
              s(:lvar, :message)), :stack))))
          end

          body = [s(:begin, *body)] if body.length > 1
          S(:class, name, s(:const, nil, :Error), *body)
        else
          body = [s(:begin, *body)] if body.length > 1
          super S(:class, name, inheritance, *body)
        end
      end
    end

    DEFAULTS.push Functions
  end
end
