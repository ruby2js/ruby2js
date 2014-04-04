module Ruby2JS
  class Converter

    # (def (self) :foo
    #   (args)
    #   (...)

    handle :defs do |target, method, args, body|
      name = @ast.loc && @ast.loc.name
      if args.children.length == 0 and name and
        name.source_buffer.source[name.end_pos] != '('
        parse s(:prop, target, method => 
          {enumerable: s(:true), configurable: s(:true),
          get: s(:block, s(:send, nil, :proc), args,
          s(:autoreturn, body))})
      elsif method =~ /=$/
        parse s(:prop, target, method.to_s.sub('=', '') => 
          {enumerable: s(:true), configurable: s(:true),
          set: s(:block, s(:send, nil, :proc), args,
          body)})
      else
        parse s(:send, target, "#{method}=", 
          s(:block, s(:send, nil, :lambda), args, body))
      end
    end
  end
end
