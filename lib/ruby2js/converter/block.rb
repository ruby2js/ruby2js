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
        [:irange, :erange].include? call.children.first.children.first.type
      then
        var = args.children.first
        expression = call.children.first.children.first
        comp = (expression.type == :irange ? '<=' : '<')
        put "for (var "; parse var; put " = "; parse expression.children.first
        put "; "; parse var; put " #{comp} "; parse expression.children.last
        put "; "; parse var; put " += "; parse call.children[2]; puts ") {"
        scope block
        sput "}"
      else
        block ||= s(:begin)
        function = s(:def, nil, args, block)
        parse s(:send, *call.children, function)
      end
    end
  end
end
