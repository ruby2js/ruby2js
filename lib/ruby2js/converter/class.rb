module Ruby2JS
  class Converter

    # (class
    #   (const nil :A)
    #   (const nil :B)
    #   (...)

    handle :class do |name, inheritance, *body|
      init = s(:def, :initialize, s(:args))
      body.compact!

      if body.length == 1 and body.first.type == :begin
        body = body.first.children.dup 
      end

      body.map! do |m| 
        if m.type == :def
          if m.children.first == :initialize
            # constructor: remove from body and overwrite init function
            init = m
            nil
          else
            # method: add to prototype
            s(:send, s(:attr, name, :prototype), "#{m.children[0]}=",
              s(:block, s(:send, nil, :proc), *m.children[1..-1]))
          end
        elsif m.type == :defs and m.children.first == s(:self)
          # class method definition: add to prototype
          s(:send, name, "#{m.children[1]}=",
            s(:block, s(:send, nil, :proc), *m.children[2..-1]))
        elsif m.type == :send and m.children.first == nil
          # class method call
          s(:send, name, *m.children[1..-1])
        elsif m.type == :lvasgn
          # class variable
          s(:send, name, "#{m.children[0]}=", *m.children[1..-1])
        elsif m.type == :casgn and m.children[0] == nil
          # class constant
          s(:send, name, "#{m.children[1]}=", *m.children[2..-1])
        else
          raise NotImplementedError, "class #{ m.type }"
        end
      end

      if inheritance
        body.unshift s(:send, name, :prototype=, s(:send, inheritance, :new))
      end

      # prepend constructor
      body.unshift s(:def, parse(name), *init.children[1..-1])

      parse s(:begin, *body.compact)
    end
  end
end
