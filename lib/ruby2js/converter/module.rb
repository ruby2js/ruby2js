module Ruby2JS
  class Converter

    # (module
    #   (const nil :A)
    #   (...)

    handle :module do |name, *body|
      symbols = [] 

      while body.length == 1 and body.first.type == :begin
        body = body.first.children
      end

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
        end
      end

      body = body - omit + [s(:return, s(:hash, 
        *symbols.map {|sym| s(:pair, s(:sym, sym), s(:lvar, sym))}))]

      body = s(:send, s(:block, s(:send, nil, :proc), s(:args),
        s(:begin, *body)), :[])
      if name.children.first == nil
        parse s(:lvasgn, name.children.last, body)
      else
        parse s(:send, name.children.first, "#{name.children.last}=", body)
      end
    end
  end
end
