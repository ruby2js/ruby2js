module Ruby2JS
  class Converter

    # (def :f
    #   (args
    #     (arg :x)
    #   (...)

    handle :def, :defm, :async do |name, args, body=nil|
      body ||= s(:begin)

      vars = {}
      vars.merge! @vars unless name
      if args and !args.children.empty?
        # splats
        if args.children.last.type == :restarg and not es2015
          if args.children[-1].children.first
            body = s(:begin, body) unless body.type == :begin
            assign = s(:lvasgn, args.children[-1].children.first,
              s(:send, s(:attr, 
                s(:attr, s(:const, nil, :Array), :prototype), :slice),
                :call, s(:lvar, :arguments),
                s(:int, args.children.length-1)))
            body = s(:begin, assign, *body.children)
          end

          args = s(:args, *args.children[0..-2])

        elsif args.children.last.type == :blockarg and
          args.children.length > 1 and args.children[-2].type == :restarg
          body = s(:begin, body) unless body.type == :begin
          blk = args.children[-1].children.first
          vararg = args.children[-2].children.first
          last = s(:send, s(:attr, s(:lvar, :arguments), :length), :-,
                  s(:int, 1))

          # set block argument to the last argument passed
          assign2 = s(:lvasgn, blk, s(:send, s(:lvar, :arguments), :[], last))

          if vararg
            # extract arguments between those defined and the last
            assign1 = s(:lvasgn, vararg, s(:send, s(:attr, s(:attr, s(:const,
              nil, :Array), :prototype), :slice), :call, s(:lvar, :arguments),
              s(:int, args.children.length-1), last))
            # push block argument back onto args if not a function
            pushback = s(:if, s(:send, s(:send, nil, :typeof, s(:lvar, blk)), 
              :"!==", s(:str, "function")), s(:begin, s(:send, s(:lvar,
              vararg), :push, s(:lvar, blk)), s(:lvasgn, blk, s(:nil))), nil)
            # set block argument to null if all arguments were defined
            pushback = s(:if, s(:send, s(:attr, s(:lvar, :arguments),
              :length), :<=, s(:int, args.children.length-2)), s(:lvasgn, 
              blk, s(:nil)), pushback)
            # combine statements
            body = s(:begin, assign1, assign2, pushback, *body.children)
          else
            # set block argument to null if all arguments were defined
            ignore = s(:if, s(:send, s(:attr, s(:lvar, :arguments),
              :length), :<=, s(:int, args.children.length-2)), s(:lvasgn, 
              blk, s(:nil)), nil)
            body = s(:begin, assign2, ignore, *body.children)
          end

          args = s(:args, *args.children[0..-3])
        end

        # optional arguments
        args.children.each_with_index do |arg, i|
          if arg.type == :optarg and not es2015
            body = s(:begin, body) unless body.type == :begin
            argname, value = arg.children
            children = args.children.dup
            children[i] = s(:arg, argname)
            args = s(:args, *children)
            body = s(:begin, body) unless body.type == :begin
            default = s(:if, s(:send, s(:defined?, s(:lvar, argname)), :!),
              s(:lvasgn, argname, value), nil)
            body = s(:begin, default, *body.children)
          end

          if arg.type == :shadowarg
            vars.delete(arg.children.first)
          else
            vars[arg.children.first] = true
          end
        end
      end

      put 'async ' if @ast.type == :async

      # es2015 fat arrow support
      if 
        not name and es2015 and @state != :method and @ast.type != :defm and 
        not @prop
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
          else
            style = :expression
          end
        elsif 
          expr.type == :if and expr.children[1] and expr.children[2] and
          EXPRESSIONS.include? expr.children[1].type and
          EXPRESSIONS.include? expr.children[2].type
        then
          style = :expression
        else
          style = :statement
        end

        if args.children.length == 1 and style == :expression
          parse args; put ' => '
        else
          put '('; parse args; put ') => '
        end

        if style == :expression
          expr.type == :hash ? group(expr) : wrap('(', ')') { parse(expr) }
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

        put '('; parse args; put ") {#{nl}"

        next_token, @next_token = @next_token, :return
        @block_depth += 1 if @block_depth
        mark = output_location
        scope body, vars
        if @block_this and @block_depth == 1
          insert mark, "#{es2015 ? 'let' : 'var'} self = this#{@sep}"
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
