module Ruby2JS
  class Converter

    # (def :f
    #   (args
    #     (arg :x)
    #   (...)

    handle :def, :defm, :async, :deff do |name, args, body=nil|
      body ||= s(:begin)

      # Detect endless method (def foo(x) = expr) and wrap body in autoreturn
      # Endless methods have loc.assignment (the =) but no loc.end
      if @ast.loc and @ast.loc.respond_to?(:assignment) and @ast.loc.assignment and
         @ast.loc.respond_to?(:end) and @ast.loc.end.nil?
        body = s(:autoreturn, body)
      end

      add_implicit_block = false

      walk = ->(node) do
        add_implicit_block = true if node.type == :yield || (node.type == :send && node.children[1] == "_implicitBlockYield")
        node.children.each do |child|
          walk[child] if child.respond_to?(:type) && child.respond_to?(:children)
        end
      end
      walk[body]

      if add_implicit_block
        children = args.children.dup
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

      put 'async ' if @ast.type == :async

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

        if EXPRESSIONS.include? expr.type
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
          EXPRESSIONS.include? expr.children[1].type and
          EXPRESSIONS.include? expr.children[2].type
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

        return
      end

      nl = @nl unless body == s(:begin)
      begin
        if @prop
          put @prop
          @prop = nil
        elsif name
          put "function #{name.to_s.sub(/[?!]$/, '')}"
        else
          put 'function'
        end

        put '('
        if args.type == :forward_args
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
      put name
      put '='
      parse value 
    end

    handle :restarg do |name|
      put '...'
      put name
    end
  end
end
