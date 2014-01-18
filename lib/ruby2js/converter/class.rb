module Ruby2JS
  class Converter

    # (class
    #   (const nil :A)
    #   (const nil :B)
    #   (...)

    # NOTE: macro :prop is defined at the bottom of this file

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
          elsif m.children.first =~ /=/
            # property setter
            sym = :"#{m.children.first.to_s[0..-2]}"
            s(:prop, s(:attr, name, :prototype), sym,
                enumerable: s(:true), configurable: s(:true),
                set: s(:block, s(:send, nil, :proc), *m.children[1..-1]))
          elsif m.children[1].children.length == 0 and m.children.first !~ /!/
            # property getter
            s(:prop, s(:attr, name, :prototype), m.children.first, 
                enumerable: s(:true), configurable: s(:true),
                get: s(:block, s(:send, nil, :proc), m.children[1],
                  s(:autoreturn, *m.children[2..-1])))
          else
            # method: add to prototype
            s(:send, s(:attr, name, :prototype),
              :"#{m.children[0].to_s.chomp('!')}=",
              s(:block, s(:send, nil, :proc), *m.children[1..-1]))
          end
        elsif m.type == :defs and m.children.first == s(:self)
          # class method definition: add to prototype
          s(:prototype, s(:send, name, "#{m.children[1]}=",
            s(:block, s(:send, nil, :proc), *m.children[2..-1])))
        elsif m.type == :send and m.children.first == nil
          if m.children[1] == :attr_accessor
            m.children[2..-1].map do |sym|
              var = sym.children.first
              s(:prop, s(:attr, name, :prototype), var, 
                  enumerable: s(:true), configurable: s(:true),
                  get: s(:block, s(:send, nil, :proc), s(:args), 
                    s(:return, s(:ivar, :"@#{var}"))),
                  set: s(:block, s(:send, nil, :proc), s(:args, s(:arg, var)), 
                    s(:ivasgn, :"@#{var}", s(:lvar, var))))
            end
          elsif m.children[1] == :attr_reader
            m.children[2..-1].map do |sym|
              var = sym.children.first
              s(:prop, s(:attr, name, :prototype), var,
                  get: s(:block, s(:send, nil, :proc), s(:args), 
                    s(:return, s(:ivar, :"@#{var}"))),
                  enumerable: s(:true),
                  configurable: s(:true))
            end
          elsif m.children[1] == :attr_writer
            m.children[2..-1].map do |sym|
              var = sym.children.first
              s(:prop, s(:attr, name, :prototype), var,
                  set: s(:block, s(:send, nil, :proc), s(:args, s(:arg, var)), 
                    s(:ivasgn, :"@#{var}", s(:lvar, var))),
                  enumerable: s(:true),
                  configurable: s(:true))
            end
          else
            # class method call
            s(:send, name, *m.children[1..-1])
          end
        elsif m.type == :lvasgn
          # class variable
          s(:send, name, "#{m.children[0]}=", *m.children[1..-1])
        elsif m.type == :cvasgn
          # class variable
          s(:send, name, "_#{m.children[0][2..-1]}=", *m.children[1..-1])
        elsif m.type == :send and m.children[0].type == :cvar
          s(:send, s(:attr, name, "_#{m.children[0].children[0][2..-1]}"),
            *m.children[1..-1])
        elsif m.type == :casgn and m.children[0] == nil
          # class constant
          s(:send, name, "#{m.children[1]}=", *m.children[2..-1])
        else
          raise NotImplementedError, "class #{ m.type }"
        end
      end

      body.flatten!

      # merge nearby property definitions
      for i in 0...body.length-1
        next unless body[i] and body[i].type == :prop
        for j in i+1...body.length
          break unless body[j] and body[j].type == :prop
          if body[i].children[0..1] == body[j].children[0..1]
            merge = body[i].children[2].merge(body[j].children[2])
            body[j] = s(:prop, *body[j].children[0..1], merge)
            body[i] = nil
          end
        end
      end

      if inheritance
        body.unshift s(:send, name, :prototype=, s(:send, inheritance, :new))
      else
        body.compact!

        # look for a sequence of methods
        methods = 0
        body.each do |node|
          break unless node
          if node.type == :send
            break unless node.children[0] and node.children[0].type == :attr
            break unless node.children[0].children[0..1] == [name, :prototype]
            break unless node.children[1] =~ /=$/
          elsif node.type != :prop
            break
          end
          methods += 1
        end

        # collapse sequence of methods to a single assignment
        if methods > 1 or (methods == 1 and body[0].type == :prop)
          pairs = body[0...methods].map do |node|
            if node.type == :send
              s(:pair, s(:str, node.children[1].to_s.chomp('=')), 
                node.children[2])
            else
              s(:pair, s(:prop, node.children[1]), node.children[2])
            end
          end
          body.shift(methods)
          body.unshift s(:send, name, :prototype=, s(:hash, *pairs))
        end
      end

      # prepend constructor
      body.unshift s(:def, parse(name), *init.children[1..-1])

      begin
        # save class name
        class_name, @class_name = @class_name, name
        # inhibit ivar substitution within a class definition.  See ivars.rb
        ivars, self.ivars = self.ivars, nil
        parse s(:begin, *body.compact)
      ensure
        self.ivars = ivars
        @class_name = class_name
      end
    end

    # macro that expands into Object.defineProperty(obj, prop, descriptor)
    handle :prop do |obj, prop, descriptor|
      parse s(:send, s(:const, nil, :Object), :defineProperty,
        obj, s(:sym, prop), s(:hash,
        *descriptor.map { |key, value| s(:pair, s(:sym, key), value) }))
    end
  end
end
