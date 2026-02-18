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

      # Check if a node contains a break statement with a value (recursively)
      # Used to detect when a loop needs to be wrapped in an IIFE
      def contains_break_with_value?(node)
        return false unless Ruby2JS.ast_node?(node)
        return true if node.type == :break && node.children.any?
        # Don't descend into nested blocks/lambdas - they have their own break scope
        return false if [:block, :lambda].include?(node.type)
        node.children.any? { |c| contains_break_with_value?(c) }
      end

      # Replace break statements with return statements (recursively)
      # Used when wrapping a loop in an IIFE to support break-with-value
      def replace_breaks_with_returns(node)
        return node unless Ruby2JS.ast_node?(node)
        if node.type == :break
          # break value -> return value; break -> return
          s(:return, *node.children)
        elsif [:block, :lambda].include?(node.type)
          # Don't descend into nested blocks - they have their own break scope
          node
        else
          node.updated(nil, node.children.map { |c| replace_breaks_with_returns(c) })
        end
      end

      # Convert a block arg (or nested mlhs) to lvasgn for for..of destructuring
      def args_to_lvasgn(child)
        if child.type == :mlhs
          s(:mlhs, *child.children.map { |c| args_to_lvasgn(c) })
        elsif child.type == :splat
          # Prism: s(:splat, s(:arg, :name))
          s(:restarg, child.children[0].children[0])
        elsif child.type == :restarg
          # whitequark parser: s(:restarg, :name)
          child
        else
          s(:lvasgn, child.children[0])
        end
      end

      # Collect all leaf arg names from an args node (handles nested mlhs)
      def collect_arg_names(node)
        names = []
        if node.type == :mlhs
          node.children.each { |c| names.push(*collect_arg_names(c)) }
        elsif node.type == :arg
          names << node.children[0]
        elsif node.type == :args
          node.children.each { |c| names.push(*collect_arg_names(c)) }
        end
        names
      end

      # Suffix all leaf arg names in an args structure (for sort_by comparison)
      def suffix_args(node, suffix)
        if node.type == :mlhs
          s(:mlhs, *node.children.map { |c| suffix_args(c, suffix) })
        elsif node.type == :arg
          s(:arg, :"#{node.children[0]}#{suffix}")
        elsif node.type == :args
          s(:args, *node.children.map { |c| suffix_args(c, suffix) })
        else
          node
        end
      end

      def initialize(*args)
        @jsx = false
        @index_result_vars = Set.new
        super
      end

      # Reset index tracking per method scope
      def on_def(node)
        @index_result_vars = Set.new
        super
      end

      def on_defs(node)
        @index_result_vars = Set.new
        super
      end

      # Track local variables assigned from .index() calls
      # so we can convert .nil? checks to === -1
      def on_lvasgn(node)
        var_name, value = node.children
        if value&.type == :send && value.children[1] == :index
          @index_result_vars << var_name
        end
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
        if result&.type == :send and node.type == :csend and
            (result.children[0] != nil or node.children[0] == nil) and
            result.children[1].to_s =~ /\A[a-zA-Z_]/
          # Only restore csend when safe:
          # - Receiver wasn't moved to an argument (to_i/to_f → parseInt)
          # - Method is still an identifier, not an operator (negative? → <)
          result = result.updated(:csend)
        elsif result&.type == :call and node.type == :csend
          # Handle &.call -> ccall (conditional call) for optional chaining
          result = result.updated(:ccall)
        end
        result
      end

      # Methods that always need () in JS even when called without args/parens in Ruby
      # These return values and must be called as methods, not accessed as properties
      FORCE_PARENS = %i[reverse pop shift sort dup clone].freeze

      def on_send(node)
        target, method, *args = node.children
        return super if excluded?(method) and method != :call

        # require 'json' → remove (JSON is built-in in JavaScript)
        if target.nil? && method == :require && args.length == 1 &&
           args.first.type == :str && args.first.children.first == 'json'
          return s(:begin)
        end

        # Force certain methods to always have () in JS output
        # Without this, is_method? heuristics treat them as property access
        if target && FORCE_PARENS.include?(method) && args.empty? && !node.is_method?
          return super node.updated(:call, node.children)
        end

        # Class.new { }.new -> object literal {}
        # Transform anonymous class instantiation to object literal
        if method == :new and target and target.type == :block
          block_call = target.children[0]
          const_node = block_call.children[0]
          if block_call.type == :send and
             const_node&.type == :const and
             const_node.children[0].nil? and const_node.children[1] == :Class and
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
                # Use explicit != -1 check (Ruby returns nil, JS returns -1 when not found)
                existing_idx = pairs.find_index { |p| p.children[0].type == :prop && p.children[0].children[0] == base_name } || -1
                if existing_idx != -1
                  # Merge with existing getter
                  existing = pairs[existing_idx]
                  pairs.slice!(existing_idx)
                  pairs << s(:pair, s(:prop, base_name),
                    {get: existing.children[1][:get], set: setter})
                else
                  pairs << s(:pair, s(:prop, base_name), {set: setter})
                end
              elsif !m.is_method? and method_args.children.empty?
                # Getter: def foo (no parens, no args) -> prop with get
                getter = s(:defm, nil, method_args, s(:autoreturn, method_body))

                # Check if there's already a setter for this property
                # Use explicit != -1 check (Ruby returns nil, JS returns -1 when not found)
                existing_idx = pairs.find_index { |p| p.children[0].type == :prop && p.children[0].children[0] == name } || -1
                if existing_idx != -1
                  # Merge with existing setter
                  existing = pairs[existing_idx]
                  pairs.slice!(existing_idx)
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

        elsif method == :call and target and target.type != :block and
          (%i[ivar cvar].include?(target.type) or not excluded?(:call))
          # Don't convert IIFE lambdas (block targets) - the send converter
          # already handles s(:send, <block>, :call) with proper grouping
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
              popped = stack.pop
              popped[-1] = token.last
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
          args.unshift target if target
          process S(:hash, *args.map {|arg| s(:kwsplat, arg)})

        elsif method == :merge!
          process S(:assign, target, *args)

        elsif method == :delete and args.length == 1
          if not target
            process S(:undef, args.first)
          elsif args.first.type == :str
            key = args.first.children.first
            # Use bracket notation if key is not a valid JS identifier
            if key =~ /\A[a-zA-Z_$][a-zA-Z0-9_$]*\z/
              process S(:undef, S(:attr, target, key))
            else
              process S(:undef, S(:send, target, :[], args.first))
            end
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
              s(:regopt, :g, *arg.children.last.children)])
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

        elsif method == :scan and args.length == 2 and args[1].type == :block
          # str.scan(/pattern/) { |match| ... } with capturing groups
          # Convert to: for (let $_ of str.matchAll(/pattern/g)) { let match = $_.slice(1); ... }
          arg = args.first
          callback = args[1]

          if arg.type == :regexp
            gpattern = arg.updated(:regexp, [*arg.children[0...-1],
              s(:regopt, :g, *arg.children.last.children)])
          else
            gpattern = s(:send, s(:const, nil, :RegExp), :new, process(arg), s(:str, 'g'))
          end

          # Extract block args and body
          block_args = callback.children[1]
          block_body = callback.children[2]

          # Build: for (let $_ of str.matchAll(/pattern/g)) { let match = $_.slice(1); body }
          match_var = :"$_"
          block_arg_name = block_args.children.first&.children&.first || :match

          s(:for_of,
            s(:lvasgn, match_var),
            s(:send, process(target), :matchAll, gpattern),
            s(:begin,
              s(:lvasgn, block_arg_name, s(:send, s(:lvar, match_var), :slice, s(:int, 1))),
              process(block_body)))

        elsif method == :gsub and args.length == 2
          before, after = args
          if before.type == :regexp
            before = before.updated(:regexp, [*before.children[0...-1],
              s(:regopt, :g, *before.children.last.children)])
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

        elsif method == :getbyte and args.length == 1
          # str.getbyte(n) → str.charCodeAt(n)
          # Note: getbyte returns byte value, charCodeAt returns char code
          # For ASCII (which is what is_method? checks for), these are equivalent
          process S(:send, target, :charCodeAt, *args)

        elsif method == :chr and args.length == 0
          if target.type == :int
            process S(:str, target.children.last.chr)
          else
            process S(:send, s(:const, nil, :String), :fromCharCode, target)
          end

        elsif method == :empty? and args.length == 0
          process S(:send, S(:attr, target, :length), :==, s(:int, 0))

        elsif method == :nil? and args.length == 0
          # If target is a local var from .index(), use === -1 instead of == null
          # because JS indexOf returns -1 (not null) when not found
          if target&.type == :lvar && @index_result_vars.include?(target.children[0])
            process S(:send, target, :===, s(:int, -1))
          else
            process S(:send, target, :==, s(:nil))
          end

        elsif method == :zero? and args.length == 0
          process S(:send, target, :===, s(:int, 0))

        elsif method == :positive? and args.length == 0
          process S(:send, target, :>, s(:int, 0))

        elsif method == :negative? and args.length == 0
          process S(:send, target, :<, s(:int, 0))

        elsif method == :any? and args.length == 0
          # arr.any? => arr.length > 0
          process S(:send, s(:attr, target, :length), :>, s(:int, 0))

        elsif method == :all? and args.length == 0
          # arr.all? => arr.every(Boolean)
          process S(:send, target, :every, s(:const, nil, :Boolean))

        elsif method == :none? and args.length == 0
          # arr.none? => arr.length === 0
          process S(:send, s(:attr, target, :length), :===, s(:int, 0))

        elsif [:start_with?, :end_with?].include? method and args.length >= 1
          js_method = method == :start_with? ? :startsWith : :endsWith
          if args.length == 1
            process S(:send, target, js_method, *args)
          else
            # Multiple args: str.start_with?('a', 'b') => ['a', 'b'].some(p => str.startsWith(p))
            process S(:send,
              S(:array, *args),
              :some,
              S(:block,
                S(:send, nil, :proc),
                S(:args, S(:arg, :_p)),
                S(:send, target, js_method, S(:lvar, :_p))))
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
          if node.type == :csend
            # x&.respond_to?(:foo) => x != null && "foo" in x
            process S(:and, S(:send, target, :!=, s(:nil)), S(:in?, args.first, target))
          else
            process S(:in?, args.first, target)
          end

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
          elsif method == :pretty_generate
            # JSON.pretty_generate(x) => JSON.stringify(x, null, 2)
            process node.updated(nil, [target, :stringify, args.first, s(:nil), s(:int, 2)])
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
              # Process target for each use so earlier filters (e.g., erb ivar->lvar)
              # can transform all copies, not just the original node
              S(:and,
                s(:and,
                  s(:send, s(:send, nil, :typeof, process(target)), :===, s(:str, "object")),
                  s(:send, process(target), :'!==', s(:nil))),
                s(:send, s(:send, s(:const, nil, :Array), :isArray, process(target)), :'!'))
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

        elsif method==:uniq and args.length == 0
          # array.uniq -> [...new Set(array)]
          process s(:array, s(:splat,
            s(:send, s(:const, nil, :Set), :new, target)))

        elsif method==:uniq! and args.length == 0
          # array.uniq! -> array.splice(0, array.length, ...new Set(array))
          process s(:send, target, :splice,
            s(:int, 0),
            s(:attr, target, :length),
            s(:splat, s(:send, s(:const, nil, :Set), :new, target)))

        elsif method==:rotate
          if args.length == 0
            # array.rotate -> [...array.slice(1), array[0]]
            process s(:array,
              s(:splat, s(:send, target, :slice, s(:int, 1))),
              s(:send, target, :[], s(:int, 0)))
          elsif args.length == 1
            # array.rotate(n) -> [...array.slice(n), ...array.slice(0, n)]
            process s(:array,
              s(:splat, s(:send, target, :slice, args.first)),
              s(:splat, s(:send, target, :slice, s(:int, 0), args.first)))
          end

        elsif method==:to_h and args.length==0
          process node.updated(nil, [s(:const, nil, :Object), :fromEntries,
            target])

        elsif method==:rstrip
          process node.updated(nil, [target, :trimEnd, *args])

        elsif method==:lstrip and args.length == 0
          process s(:send!, target, :trimStart)

        elsif method == :index and parens_or_included?(node, method)
          if args.length == 1 && args.first.type == :regexp
            process node.updated(nil, [target, :search, *args])
          else
            process node.updated(nil, [target, :indexOf, *args])
          end

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

        elsif method == :round and args.length == 1 and target != s(:const, nil, :Math)
          # round(n) -> Math.round(x * 10**n) / 10**n
          arg = process args.first
          ptarget = process target
          multiplier = S(:send, s(:int, 10), :**, arg)
          scaled = S(:send, ptarget, :*, multiplier)
          rounded = S(:send, s(:const, nil, :Math), :round, scaled)
          S(:send, rounded, :/, multiplier)

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
            first = range.children.first
            unless first.type == :int && first.children.first == 0
              raw = s(:send, raw, :+, first)
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

        # Function.new { } => function() {} (regular function, not arrow)
        # This is needed when you need dynamic `this` binding (e.g., for filter composition)
        # Note: Use element-by-element comparison for JS compatibility (JS compares arrays by reference)
        if call.children[0]&.type == :const &&
           call.children[0].children[0] == nil &&
           call.children[0].children[1] == :Function &&
           method == :new
          args = node.children[1]
          body = node.children[2]
          # Use :deff to force regular function syntax instead of arrow function
          return process(node.updated(:deff, [nil, args, body]))
        end

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

        elsif method == :to_h and call.children.length == 2
          # arr.to_h { |x| [k, v] } => Object.fromEntries(arr.map(x => [k, v]))
          target = call.children.first
          map_block = s(:block,
            s(:send, target, :map),
            node.children[1],
            s(:autoreturn, *node.children[2..-1]))
          process s(:send, s(:const, nil, :Object), :fromEntries, map_block)

        elsif method == :compact and call.children.length == 2
          # compact with a block is NOT the array compact method
          # (e.g., serializer.compact { ... } should not become filter)
          # Skip on_send processing by constructing the call node directly
          target = call.children.first
          processed_call = call.updated(nil, [process(target), :compact])
          node.updated nil, [processed_call, process(node.children[1]),
            *process_all(node.children[2..-1])]

        elsif [:select, :find_all].include?(method) and call.children.length == 2
          call = call.updated nil, [call.children.first, :filter]
          node.updated nil, [process(call), process(node.children[1]),
            s(:autoreturn, *process_all(node.children[2..-1]))]

        elsif method == :reject and call.children.length == 2
          # arr.reject { |x| cond } => arr.filter(x => !(cond))
          call = call.updated nil, [call.children.first, :filter]
          body = node.children[2]

          if body&.type == :begin && body.children.length > 1
            # Multi-statement block: negate only the last statement
            # Use explicit slicing instead of splat to avoid selfhost transpilation issues
            children = body.children
            setup = children[0...-1]  # All but last
            last_stmt = children[-1]  # Last element
            processed_setup = process_all(setup)
            processed_last = process(last_stmt)
            negated_last = s(:send, s(:begin, processed_last), :!)
            new_body = s(:begin, *processed_setup, negated_last)
            node.updated nil, [process(call), process(node.children[1]),
              s(:autoreturn, new_body)]
          else
            # Single-statement block: negate the whole thing
            processed_body = process_all(node.children[2..-1])
            negated_body = s(:send, s(:begin, *processed_body), :!)
            node.updated nil, [process(call), process(node.children[1]),
              s(:autoreturn, negated_body)]
          end

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
          return super unless args  # Ruby 3.4 it blocks handled by converter
          block_body = node.children[2]
          # Unwrap :return node from &:symbol syntax (processor.rb wraps in return)
          block_body = block_body.children.first if block_body&.type == :return

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
          return super unless args  # Ruby 3.4 it blocks handled by converter
          block_body = node.children[2]
          # Unwrap :return node from &:symbol syntax (processor.rb wraps in return)
          block_body = block_body.children.first if block_body&.type == :return

          # Create two argument sets for the comparison function.
          # Handle nested destructuring: |(pid, cid), _| has mlhs children
          all_names = collect_arg_names(args)

          # Replace references to all block args with _a and _b suffixed versions
          key_a = block_body
          key_b = block_body
          all_names.each do |name|
            key_a = replace_lvar(key_a, name, :"#{name}_a")
            key_b = replace_lvar(key_b, name, :"#{name}_b")
          end

          # Build comparison: key_a < key_b ? -1 : key_a > key_b ? 1 : 0
          comparison = s(:if,
            s(:send, key_a, :<, key_b),
            s(:int, -1),
            s(:if,
              s(:send, key_a, :>, key_b),
              s(:int, 1),
              s(:int, 0)))

          # Build comparison function args with _a and _b suffixed names
          compare_args = s(:args, *args.children.map { |c| suffix_args(c, '_a') },
                                  *args.children.map { |c| suffix_args(c, '_b') })

          # For destructuring, wrap each comparison arg in mlhs
          if args.children.length > 1 || args.children.first.type == :mlhs
            arg_a_parts = args.children.map { |c| suffix_args(c, '_a') }
            arg_b_parts = args.children.map { |c| suffix_args(c, '_b') }
            compare_args = s(:args, s(:mlhs, *arg_a_parts), s(:mlhs, *arg_b_parts))
          end

          compare_block = s(:block,
            s(:send, nil, :proc),
            compare_args,
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
          return super unless args  # Ruby 3.4 it blocks handled by converter
          block_body = node.children[2]
          # Unwrap :return node from &:symbol syntax (processor.rb wraps in return)
          block_body = block_body.children.first if block_body&.type == :return

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
          return super unless args  # Ruby 3.4 it blocks handled by converter
          block_body = node.children[2]
          # Unwrap :return node from &:symbol syntax (processor.rb wraps in return)
          block_body = block_body.children.first if block_body&.type == :return

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
          return super unless args  # Ruby 3.4 it blocks handled by converter
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
          # If the loop contains break-with-value, wrap in IIFE and use return
          body = node.children[2]
          if contains_break_with_value?(body)
            # Wrap in IIFE: (() => { while(true) { ... return value ... } })()
            transformed_body = replace_breaks_with_returns(body)
            s(:send, s(:block, s(:send, nil, :lambda), s(:args),
              S(:while, s(:true), process(transformed_body))), :call)
          else
            S(:while, s(:true), process(body))
          end

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
          node.children[1].children.length <= 1
        then
          lvasgn = if node.children[1].children.length == 1
            s(:lvasgn, node.children[1].children[0].children[0])
          else
            s(:lvasgn, :_)
          end
          process s(:for, lvasgn,
            call.children[0].children[0], node.children[2])

        elsif \
          [:each, :each_value].include? method
        then
          if node.children[1].children.length == 0
            # No block args: collection.each do; ...; end
            process node.updated(:for_of,
              [s(:lvasgn, :_),
              node.children[0].children[0], node.children[2]])
          elsif node.children[1].children.length > 1
            process node.updated(:for_of,
              [s(:mlhs, *node.children[1].children.map {|child|
                args_to_lvasgn(child)}),
              node.children[0].children[0], node.children[2]])
          elsif node.children[1].children[0].type == :mlhs
            process node.updated(:for_of,
              [s(:mlhs, *node.children[1].children[0].children.map {|child|
                args_to_lvasgn(child)}),
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
          # Handle Ruby 3.4's `it` implicit block parameter (args is nil)
          args = node.children[1]
          arg_name = args&.children&.first&.children&.first || :it
          process node.updated(:send, [s(:block, s(:send, nil, :proc),
            args, s(:begin, node.children[2],
            s(:return, s(:lvar, arg_name)))),
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

      # Convert Struct.new to a class definition
      # Color = Struct.new(:name, :value) becomes:
      # class Color {
      #   constructor(name, value) { this.name = name; this.value = value }
      #   get name() { return this._name }
      #   set name(v) { this._name = v }
      #   ...
      # }
      def on_casgn(node)
        cbase, name, value = node.children

        # Only handle top-level constant assignment of Struct.new
        if cbase.nil? && value&.type == :send
          target, method, *args = value.children

          # Check for Struct.new - use element comparison for JS compatibility
          # (array == array doesn't work in JS)
          if target&.type == :const &&
             target.children[0].nil? && target.children[1] == :Struct &&
             method == :new &&
             args.all? { |a| a.type == :sym }

            # Extract field names from Struct.new(:field1, :field2, ...)
            fields = args.map { |a| a.children.first }

            # Build constructor args: s(:args, s(:arg, :field1), s(:arg, :field2), ...)
            constructor_args = s(:args, *fields.map { |f| s(:arg, f) })

            # Build constructor body: this._field1 = field1; etc.
            # Use ivars for storage so accessors can use them
            assignments = fields.map { |f| s(:ivasgn, :"@#{f}", s(:lvar, f)) }
            constructor_body = assignments.length == 1 ? assignments.first : s(:begin, *assignments)

            # Build class with constructor and attr_accessor for each field
            constructor = s(:def, :initialize, constructor_args, constructor_body)
            attr_accessor = s(:send, nil, :attr_accessor, *fields.map { |f| s(:sym, f) })
            class_node = s(:class, s(:const, nil, name), nil,
              s(:begin, attr_accessor, constructor))

            return process class_node
          end
        end

        super
      end

      # Map Ruby exception classes to JavaScript equivalents
      def on_const(node)
        # JSON::ParserError => SyntaxError (JSON.parse throws SyntaxError in JS)
        # Note: Use element comparison for JS compatibility (array == doesn't work in JS)
        if node.children.length == 2 &&
           node.children[0] == s(:const, nil, :JSON) &&
           node.children[1] == :ParserError
          s(:const, nil, :SyntaxError)

        # StandardError => Error (Ruby's base exception maps to JS Error)
        elsif node.children[0].nil? && node.children[1] == :StandardError
          s(:const, nil, :Error)

        # RuntimeError => Error
        elsif node.children[0].nil? && node.children[1] == :RuntimeError
          s(:const, nil, :Error)

        else
          super
        end
      end
    end

    DEFAULTS.push Functions
  end
end
