module Ruby2JS
  class Converter

    # (send nil :puts
    #   (int 1))

    # (attr nil :puts
    #   (int 1))

    handle :send, :attr do |receiver, method, *args|
      ast = @ast

      if method =~ /\w[!?]$/
        raise NotImplementedError, "invalid method name #{ method }"
      end

      # three ways to define anonymous functions
      if method == :new and receiver and receiver.children == [nil, :Proc]
        return parse args.first
      elsif not receiver and [:lambda, :proc].include? method
        return parse args.first
      end

      # call anonymous function
      if [:call, :[]].include? method and receiver and receiver.type == :block 
        t2,m2,*args2 = receiver.children.first.children
        if not t2 and [:lambda, :proc].include? m2 and args2.length == 0
          return parse s(:send, nil, parse(receiver), *args)
        end
      end

      op_index   = operator_index method
      if op_index != -1
        target = args.first 
        target = target.children.first if target and target.type == :begin
        receiver = receiver.children.first if receiver.type == :begin
      end

      group_receiver = receiver.type == :send && op_index <= operator_index( receiver.children[1] ) if receiver
      group_target = target.type == :send && op_index <= operator_index( target.children[1] ) if target

      if method == :!
        if receiver.type == :defined?
          parse s(:undefined?, *receiver.children)
        else
          group_receiver ||= (receiver.type != :send && receiver.children.length > 1)
          "!#{ group_receiver ? group(receiver) : parse(receiver) }"
        end

      elsif method == :[]
        "#{ parse receiver }[#{ args.map {|arg| parse arg}.join(', ') }]"

      elsif method == :[]=
        "#{ parse receiver }[#{ args[0..-2].map {|arg| parse arg}.join(', ') }] = #{ parse args[-1] }"

      elsif [:-@, :+@, :~].include? method
        "#{ method.to_s[0] }#{ parse receiver }"

      elsif method == :=~
        "#{ parse args.first }.test(#{ parse receiver })"

      elsif method == :!~
        "!#{ parse args.first }.test(#{ parse receiver })"

      elsif OPERATORS.flatten.include? method
        "#{ group_receiver ? group(receiver) : parse(receiver) } #{ method } #{ group_target ? group(target) : parse(target) }"  

      elsif method =~ /=$/
        "#{ parse receiver }#{ '.' if receiver }#{ method.to_s.sub(/=$/, ' =') } #{ parse args.first }"

      elsif method == :new and receiver
        args = args.map {|a| parse a}.join(', ')
        if args.length > 0 or is_method?(ast)
          "new #{ parse receiver }(#{ args })"
        else
          "new #{ parse receiver }"
        end

      elsif method == :raise and receiver == nil
        if args.length == 1
          "throw #{ parse args.first }"
        else
          "throw new #{ parse args.first }(#{ parse args[1] })"
        end

      elsif method == :typeof and receiver == nil
        "typeof #{ parse args.first }"

      else
        if args.length == 0 and not is_method?(ast)
          if receiver
            "#{ parse receiver }.#{ method }"
          else
            parse s(:lvasgn, method), @state
          end
        elsif args.length > 0 and args.last.type == :splat
          parse s(:send, s(:attr, receiver, method), :apply, receiver, 
            s(:send, s(:array, *args[0..-2]), :concat,
              args[-1].children.first))
        else
          call = "#{ parse receiver }#{ '.' if receiver }#{ method }"
          args = args.map {|a| parse a}
          if args.any? {|arg| arg.to_s.include? "\n"}
            "#{ call }(#{ args.join(', ') })"
          elsif args.map {|arg| arg.length+2}.reduce(&:+).to_i < 70
            "#{ call }(#{ args.join(', ') })"
          else
            "#{ call }(#@nl#{ args.join(",#@ws") }#@nl)"
          end
        end
      end
    end
  end
end
