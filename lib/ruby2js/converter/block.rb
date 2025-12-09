module Ruby2JS
  class Converter

    # (block
    #   (send nil :x)
    #   (args
    #     (arg :a))
    #   (lvar :a))

    handle :block do |call, args, block|

      # Check for trailing `async` arg in block call: `it "works", async do end`
      # Using element-wise comparison for selfhost JS compatibility
      last_arg = call.children.last
      is_async_arg = last_arg.respond_to?(:type) &&
                     last_arg.type == :send &&
                     last_arg.children[0] == nil &&
                     last_arg.children[1] == :async &&
                     last_arg.children.length == 2
      if is_async_arg
        return parse call.updated(nil, [*call.children[0..-2],
        s(:send, nil, :async, s(:block, s(:send, nil, :proc), args, block))])
      end

      if \
        @state == :statement and args.children.length == 1 and
        call.children.first and call.children.first.type == :begin and
        call.children[1] == :step and
        [:irange, :erange].include? call.children.first.children.first.type
      then
        begin
          vars = @vars.dup # Pragma: hash
          next_token, @next_token = @next_token, :continue

          # convert combinations of range, step and block to a for loop
          var = args.children.first
          expression = call.children.first.children.first
          comp = (expression.type == :irange ? '<=' : '<')
          put "for (let "; 
          parse var; put " = "; parse expression.children.first
          put "; "; parse var; 
          if call.children[2].type == :int and call.children[2].children[0] < 0
            put " #{comp.sub('<', '>')} "; parse expression.children.last
            put "; "; parse s(:op_asgn, var, :-, 
              s(:int, -call.children[2].children[0])), :statement
          else
            put " #{comp} "; parse expression.children.last
            put "; "; parse s(:op_asgn, var, :+, call.children[2]), :statement
          end
          puts ") {"
          scope block
          sput "}"
        ensure
          @next_token = next_token
          @vars = vars
        end

      elsif \
        call.children[0] == nil and call.children[1] == :function and
        call.children[2..-1].all? do |child|
          child.type == :lvar or (child.type == :send and
            child.children.length == 2 and child.children[0] == nil and 
            child.children[1].is_a?(Symbol))
        end
      then
        # accommodate javascript style syntax: convert function blocks with
        # simple arguments into an anonymous function
        args = call.children[2..-1].map {|arg| s(:arg, arg.children.last)}
        parse @ast.updated(:block, [s(:send, nil, :proc),
          s(:args, *args), block])

      else
        # convert blocks into method calls with an additional argument
        # consisting of an anonymous function
        block ||= s(:begin)
        function = @ast.updated(:def, [nil, args, block])
        parse s(call.type, *call.children, function), @state
      end
    end

    # (numblock
    #   (send nil :x)
    #   1
    #   (lvar :_1))

    handle :numblock do |call, count, block|
      parse s(:block,
        call,
        s(:args, *((1..count).map {|i| s(:arg, "_#{i}")})),
        block
      )
    end

  end
end
