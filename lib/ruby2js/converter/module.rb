module Ruby2JS
  class Converter

    # (module
    #   (const nil :A)
    #   (...)
    #
    #   Note: modules_hash is an anonymous modules as a value in a hash; the
    #         name has already been output so should be ignored other than
    #         in determining the namespace.

    handle :module, :module_hash do |name, *body|
      extend = @namespace.enter(name)

      if body.length == 1 && body.first == nil
        if @ast.type == :module and not extend
          parse @ast.updated(:casgn, [*name.children, s(:hash)])
        else
          parse @ast.updated(:hash, [])
        end

        @namespace.leave
        return
      end

      while body.length == 1 and body.first&.type == :begin
        body = body.first.children
      end

      if body.length > 0 and body.all? {|child|
        %i[def module].include? child.type or
        (child.type == :class and child.children[1] == nil)}

        if extend
          parse s(:assign, name, @ast.updated(:class_module, 
            [nil, nil, *body])), :statement
        elsif @ast.type == :module_hash
          parse @ast.updated(:class_module, [nil, nil, *body])
        else
          parse @ast.updated(:class_module, [name, nil, *body])
        end

        @namespace.leave
        return
      end

      symbols = [] 
      visibility = :public
      omit = []

      body.each do |node|
        if node.type == :send and node.children.first == nil
          if [:public, :private, :protected].include? node.children[1]
            if node.children.length == 2
              visibility = node.children[1]
              omit << node
            elsif node.children[1] == :public
              omit << node
              node.children[2..-1].each do |sym|
                symbols << sym.children.first if sym.type == :sym 
              end
            end
          end
        end

        next unless visibility == :public

        if node.type == :casgn and node.children.first == nil
          symbols << node.children[1]
        elsif node.type == :def
          symbols << node.children.first
        elsif node.type == :class and node.children.first.children.first == nil
          symbols << node.children.first.children.last
        elsif node.type == :module
          symbols << node.children.first.children.last
        end
      end

      body = body.reject {|node| omit.include? node}.concat([s(:return, s(:hash,
        *symbols.map {|sym| s(:pair, s(:sym, sym), s(:lvar, sym))}))])

      body = s(:send, s(:block, s(:send, nil, :proc), s(:args),
        s(:begin, *body)), :[])
      if not name
        parse body
      elsif extend
        parse s(:assign, name, body)
      elsif name.children.first == nil
        # Use casgn for const declaration (consistent with class_module)
        parse s(:casgn, nil, name.children.last, body), :statement
      else
        parse s(:send, name.children.first, "#{name.children.last}=", body)
      end

      @namespace.leave
    end
  end
end
