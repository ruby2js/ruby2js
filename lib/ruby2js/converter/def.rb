module Ruby2JS
  class Converter

    # (def :f
    #   (args
    #     (arg :x)
    #   (...)

    handle :def, :defm, :async, :deff, :defget do |name, args, body=nil|
      body ||= s(:begin)

      # Detect endless method (def foo(x) = expr) and wrap body in autoreturn
      # Endless methods have loc.assignment (the =) but no loc.end
      if @ast.loc and @ast.loc.respond_to?(:assignment) and @ast.loc.assignment and
         @ast.loc.respond_to?(:end) and @ast.loc.end.nil?
        body = s(:autoreturn, body)
      end

      # Handle blockarg after restarg: def f(*args, &block)
      # JS doesn't allow params after rest, so we pop block from args at runtime
      block_arg_after_rest = nil
      if args
        has_restarg = args.children.any? { |a| a.type == :restarg }
        last_arg = args.children.last
        if has_restarg && last_arg&.type == :blockarg
          block_arg_after_rest = last_arg.children.first
          # Get the restarg name for the pop
          restarg = args.children.find { |a| a.type == :restarg }
          restarg_name = restarg.children.first || 'args'
          # Remove blockarg from args
          args = s(:args, *args.children[0..-2])
          # Prepend: let block = restarg.pop()
          pop_stmt = s(:lvasgn, block_arg_after_rest,
            s(:send, s(:lvar, restarg_name), :pop))
          if body.type == :begin
            body = s(:begin, pop_stmt, *body.children)
          else
            body = s(:begin, pop_stmt, body)
          end
        end
      end

      # Handle kwargs after restarg: def f(*args, opt: default)
      # JS doesn't allow params after rest, so extract kwargs from last element
      if args
        kwarg_types = [:kwarg, :kwoptarg, :kwrestarg]
        has_restarg = args.children.any? { |a| a.type == :restarg }
        kwargs = args.children.select { |a| kwarg_types.include?(a.type) }

        if has_restarg && !kwargs.empty?
          restarg = args.children.find { |a| a.type == :restarg }
          restarg_name = restarg.children.first || 'args'

          # Remove kwargs from args
          args = s(:args, *args.children.reject { |a| kwarg_types.include?(a.type) })

          # Build destructuring: let { opt = default } = restarg.at(-1)?.constructor === Object ? restarg.pop() : {}
          # For simplicity, use: let { opt = default } = typeof restarg.at(-1) === 'object' && restarg.at(-1)?.constructor === Object ? restarg.pop() : {}
          # Even simpler pattern that works: extract options if last arg is plain object
          kwarg_names = []
          kwarg_defaults = {}
          kwargs.each do |kw|
            if kw.type == :kwarg
              kwarg_names << kw.children.first
            elsif kw.type == :kwoptarg
              kwarg_names << kw.children.first
              kwarg_defaults[kw.children.first] = kw.children.last
            end
          end

          # Create: let $opts = restarg.at(-1)
          # Create: if (typeof $opts === 'object' && $opts !== null && $opts.constructor === Object) { restarg.pop() } else { $opts = {} }
          # Create: let { opt1, opt2 = default } = $opts
          opts_var = :$kwargs

          # $opts = restarg.at(-1)
          opts_init = s(:lvasgn, opts_var, s(:send, s(:lvar, restarg_name), :at, s(:int, -1)))

          # typeof $opts === 'object' && $opts !== null && $opts.constructor === Object
          # Use :! and :== instead of :!== since Ruby symbols can't contain ==
          # Use :attr for property access (not method call)
          is_plain_object = s(:and,
            s(:and,
              s(:send, s(:send, nil, :typeof, s(:lvar, opts_var)), :===, s(:str, 'object')),
              s(:send, s(:send, s(:lvar, opts_var), :==, s(:nil)), :!)),
            s(:send, s(:attr, s(:lvar, opts_var), :constructor), :===, s(:const, nil, :Object)))

          # if check then restarg.pop() else $opts = {}
          conditional = s(:if, is_plain_object,
            s(:send, s(:lvar, restarg_name), :pop),
            s(:lvasgn, opts_var, s(:hash)))

          # Destructure: let { k1, k2 = default } = $opts
          pairs = kwarg_names.map do |kw_name|
            if kwarg_defaults[kw_name]
              s(:pair, s(:sym, kw_name), kwarg_defaults[kw_name])
            else
              s(:pair, s(:sym, kw_name), s(:lvar, kw_name))
            end
          end
          destructure = s(:lvasgn, s(:hash_pattern, *kwarg_names.map { |n|
            if kwarg_defaults[n]
              s(:match_var_with_default, n, kwarg_defaults[n])
            else
              s(:match_var, n)
            end
          }), s(:lvar, opts_var))

          # Simpler approach: just use direct assignment for each kwarg
          kwarg_stmts = []
          kwarg_stmts << opts_init
          kwarg_stmts << conditional
          kwarg_names.each do |kw_name|
            if kwarg_defaults[kw_name]
              # let kw = $opts.kw ?? default (nullish coalescing handles undefined)
              # Use :attr for property access and :nullish for ?? operator
              kwarg_stmts << s(:lvasgn, kw_name,
                s(:nullish, s(:attr, s(:lvar, opts_var), kw_name), kwarg_defaults[kw_name]))
            else
              # let kw = $opts.kw (required kwarg)
              kwarg_stmts << s(:lvasgn, kw_name, s(:attr, s(:lvar, opts_var), kw_name))
            end
          end

          if body.type == :begin
            body = s(:begin, *kwarg_stmts, *body.children)
          elsif body
            body = s(:begin, *kwarg_stmts, body)
          else
            body = s(:begin, *kwarg_stmts)
          end
        end
      end

      add_implicit_block = false
      contains_await = false

      walk = ->(node) do
        add_implicit_block = true if node.type == :yield || (node.type == :send && node.children[1] == "_implicitBlockYield")
        # Detect await nodes - if body contains await, function must be async
        contains_await = true if node.type == :await || node.type == :await!
        node.children.each do |child|
          walk.call(child) if ast_node?(child)
        end
      end
      walk.call(body)

      if add_implicit_block
        children = args.children.dup # Pragma: array
        children.push s(:optarg, "_implicitBlockYield", s(:nil))
        args = s(:args, *children)
      end

      vars = {}
      vars.merge! @vars unless name
      if args and !args.children.empty?
        args.children.each do |arg|
          if arg.type == :shadowarg
            vars.delete(arg.children.first)
          else
            vars[arg.children.first] = true
          end
        end
      end

      # Add async if explicitly marked or if body contains await
      put 'async ' if @ast.type == :async || contains_await

      # fat arrow support
      if \
        not name and @state != :method and @ast.type != :defm and
        @ast.type != :deff and not @prop
      then
        expr = body
        expr = expr.children.first while expr.type == :autoreturn
        while expr.type == :begin and expr.children.length == 1
          expr = expr.children.first
        end
        expr = expr.children.first if expr.type == :return

        if Converter::EXPRESSIONS.include? expr.type
          if expr.type == :send and expr.children[0..1] == [nil, :raise]
            style = :statement
          elsif expr.type == :send and expr.children.length == 2 and
            expr.children.first == nil and @rbstack.last and
            @rbstack.last[expr.children[1]]&.type == :autobind
            style = :statement
          else
            style = :expression
          end
        elsif \
          expr.type == :if and expr.children[1] and expr.children[2] and
          Converter::EXPRESSIONS.include? expr.children[1].type and
          Converter::EXPRESSIONS.include? expr.children[2].type
        then
          style = :expression
        else
          style = :statement
        end

        if args.children.length == 1 and args.children.first.type == :arg and style == :expression
          parse args; put ' => '
        else
          put '('; parse args; put ') => '
        end

        # Arrow functions are new function scopes - next should become return
        next_token, @next_token = @next_token, :return
        begin
          if style == :expression
            if expr.type == :taglit
              parse expr
            elsif expr.type == :hash
              group(expr)
            else
              wrap('(', ')') { parse(expr) }
            end
          elsif body.type == :begin and body.children.length == 0
            put "{}"
          else
            put "{#{@nl}"; scope body, vars; put "#{@nl}}"
          end
        ensure
          @next_token = next_token
        end

        return
      end

      nl = @nl unless body == s(:begin)
      begin
        if @prop
          put @prop
          @prop = nil
        elsif name
          put "function #{jsvar(name.to_s.sub(/[?!]$/, ''))}"
        else
          put 'function'
        end

        put '('
        if args.nil?
          # Method with no arguments
        elsif args.type == :forward_args
          parse args
        else
          parse s(:args, *args.children.select {|arg| arg.type != :shadowarg})
        end
        put ") {#{nl}"

        next_token, @next_token = @next_token, :return
        @block_depth += 1 if @block_depth
        mark = output_location
        scope body, vars
        if @block_this and @block_depth == 1
          insert mark, "let self = this#{@sep}"
          @block_this = false
        end

        put "#{nl}}"
      ensure
        @next_token = next_token
        @block_depth -= 1 if @block_depth
      end
    end

    handle :optarg do |name, value|
      put jsvar(name)
      put '='
      parse value
    end

    handle :restarg do |name=nil|
      put '...'
      put jsvar(name) if name
    end
  end
end
