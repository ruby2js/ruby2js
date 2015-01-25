module Ruby2JS
  class Converter

    # (def :f
    #   (args
    #     (arg :x)
    #   (...)

    handle :def do |name, args, body=nil|
      body ||= s(:begin)
      if name =~ /[!?]$/
        raise NotImplementedError, "invalid method name #{ name }"
      end

      vars = {}
      vars.merge! @vars unless name
      if args and !args.children.empty?
        # splats
        if args.children.last.type == :restarg
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
          if arg.type == :optarg
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

      nl = @nl unless body == s(:begin)
      begin
        next_token, @next_token = @next_token, :return
        @block_depth += 1 if @block_depth
        body = scope body, vars
        if @block_this and @block_depth == 1
          body = "var self = this#{@sep}#{body}"
        end

        "function#{ " #{name}" if name }(#{ parse args }) {#{nl}#{ body }#{nl}}"
      ensure
        @next_token = next_token
        @block_depth -= 1 if @block_depth
      end
    end
  end
end
