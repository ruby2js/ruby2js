module Ruby2JS
  class Converter

    # (block
    #   (send nil :x)
    #   (args
    #     (arg :a))
    #   (lvar :a))

    handle :block do |call, args, block|

      if
        @state == :statement and args.children.length == 1 and
        call.children.first and call.children.first.type == :begin and
        call.children[1] == :step and
        [:irange, :erange].include? call.children.first.children.first.type
      then
        begin
          next_token, @next_token = @next_token, :continue

          # convert combinations of range, step and block to a for loop
          var = args.children.first
          expression = call.children.first.children.first
          comp = (expression.type == :irange ? '<=' : '<')
          put "for (var "; parse var; put " = "; parse expression.children.first
          put "; "; parse var; 
          if call.children[2].type == :int and call.children[2].children[0] < 0
            put " #{comp.sub('<', '>')} "; parse expression.children.last
            put "; "; parse var; put " -= "
            parse s(:int, -call.children[2].children[0])
          else
            put " #{comp} "; parse expression.children.last
            put "; "; parse var; put " += "; parse call.children[2]
          end
          puts ") {"
          scope block
          sput "}"
        ensure
          @next_token = next_token
        end

      elsif
        call.children[0] == nil and call.children[1] == :function and
        call.children[2..-1].all? do |child|
          child.type == :lvar or (child.type == :send and
            child.children.length == 2 and child.children[0] == nil and 
            Symbol === child.children[1])
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
        parse s(@ast.children[0].type, *call.children, function)
      end
    end
  end
end
