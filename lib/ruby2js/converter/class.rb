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
      else
        # look for a sequence of methods
        methods = 0
        body.compact!.each do |node|
          break unless node and node.type == :send and node.children[0]
          break unless node.children[0].type == :attr
          break unless node.children[0].children[0..1] == [name, :prototype]
          break unless node.children[1] =~ /=$/
          methods += 1
        end

        # collapse sequence of methods to a single assignment
        if methods > 1
          pairs = body[0...methods].map do |node|
            s(:pair, s(:str, node.children[1].chomp('=')), node.children[2])
          end
          body.shift(methods)
          body.unshift s(:send, name, :prototype=, s(:hash, *pairs))
        end
      end

      # prepend constructor
      body.unshift s(:def, parse(name), *init.children[1..-1])

      parse s(:begin, *body.compact)
    end
  end
end
