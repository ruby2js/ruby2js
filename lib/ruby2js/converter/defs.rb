module Ruby2JS
  class Converter

    # (defs (self) :foo
    #   (args)
    #   (...)

    # NOTE: defp and asyncs are only produced by filters

    handle :defs, :defp, :asyncs do |target, method, args, body|
      node = transform_defs(target, method, args, body)

      if node.type == :send and @ast.type == :asyncs
        node = node.updated(nil, [*node.children[0..1],
          node.children[2].updated(:async)])
      end

      parse node
    end

    def transform_defs(target, method, args, body)
      if not @ast.is_method? or @ast.type == :defp
        node = s(:prop, target, method.to_s =>
          {enumerable: s(:true), configurable: s(:true),
          get: s(:block, s(:send, nil, :proc), args,
          s(:autoreturn, body))})
      elsif method =~ /=$/
        node = s(:prop, target, method.to_s.sub('=', '') =>
          {enumerable: s(:true), configurable: s(:true),
          set: s(:block, s(:send, nil, :proc), args,
          body)})
      else
        node = s(:send, target, "#{method}=", s(:def, nil, args, body))
      end

      @comments[node] = @comments[@ast] if @comments[@ast]

      node
    end
  end
end
