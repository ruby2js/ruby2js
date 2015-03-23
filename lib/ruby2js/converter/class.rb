module Ruby2JS
  class Converter

    # (class
    #   (const nil :A)
    #   (const nil :B)
    #   (...)

    # NOTE: :prop and :method macros are defined at the bottom of this file

    handle :class do |name, inheritance, *body|
      if inheritance
        init = s(:def, :initialize, s(:args), s(:super))
      else
        init = s(:def, :initialize, s(:args), nil)
      end

      body.compact!

      if body.length == 1 and body.first.type == :begin
        body = body.first.children.dup 
      end

      body.compact!
      visible = {}
      body.map! do |m| 
        if m.type == :def
          if m.children.first == :initialize
            # constructor: remove from body and overwrite init function
            init = m
            nil
          elsif m.children.first =~ /=/
            # property setter
            sym = :"#{m.children.first.to_s[0..-2]}"
            s(:prop, s(:attr, name, :prototype), sym =>
                {enumerable: s(:true), configurable: s(:true),
                set: s(:block, s(:send, nil, :proc), *m.children[1..-1])})
          else
            visible[m.children[0]] = s(:self)

            if not m.is_method?
              # property getter
              s(:prop, s(:attr, name, :prototype), m.children.first =>
                  {enumerable: s(:true), configurable: s(:true),
                  get: s(:block, s(:send, nil, :proc), m.children[1],
                    s(:autoreturn, *m.children[2..-1]))})
            else
              # method: add to prototype
              s(:method, s(:attr, name, :prototype),
                :"#{m.children[0].to_s.chomp('!')}=",
                s(:block, s(:send, nil, :proc), *m.children[1..-1]))
            end
          end

        elsif m.type == :defs and m.children.first == s(:self)
          if m.children[1] =~ /=$/
            # class property setter
            s(:prop, name, m.children[1].to_s[0..-2] =>
                {enumerable: s(:true), configurable: s(:true),
                set: s(:block, s(:send, nil, :proc), *m.children[2..-1])})
          elsif m.children[2].children.length == 0 and
            m.children[1] !~ /!/ and m.loc and m.loc.name and
            m.loc.name.source_buffer.source[m.loc.name.end_pos] != '('

            # class property getter
            s(:prop, name, m.children[1].to_s =>
                {enumerable: s(:true), configurable: s(:true),
                get: s(:block, s(:send, nil, :proc), m.children[2],
                  s(:autoreturn, *m.children[3..-1]))})
          else
            # class method definition: add to prototype
            s(:prototype, s(:send, name, "#{m.children[1]}=",
              s(:block, s(:send, nil, :proc), *m.children[2..-1])))
          end

        elsif m.type == :send and m.children.first == nil
          if m.children[1] == :attr_accessor
            m.children[2..-1].map do |sym|
              var = sym.children.first
              s(:prop, s(:attr, name, :prototype), var =>
                  {enumerable: s(:true), configurable: s(:true),
                  get: s(:block, s(:send, nil, :proc), s(:args), 
                    s(:return, s(:ivar, :"@#{var}"))),
                  set: s(:block, s(:send, nil, :proc), s(:args, s(:arg, var)), 
                    s(:ivasgn, :"@#{var}", s(:lvar, var)))})
            end
          elsif m.children[1] == :attr_reader
            m.children[2..-1].map do |sym|
              var = sym.children.first
              s(:prop, s(:attr, name, :prototype), var =>
                  {get: s(:block, s(:send, nil, :proc), s(:args), 
                    s(:return, s(:ivar, :"@#{var}"))),
                  enumerable: s(:true),
                  configurable: s(:true)})
            end
          elsif m.children[1] == :attr_writer
            m.children[2..-1].map do |sym|
              var = sym.children.first
              s(:prop, s(:attr, name, :prototype), var =>
                  {set: s(:block, s(:send, nil, :proc), s(:args, s(:arg, var)), 
                    s(:ivasgn, :"@#{var}", s(:lvar, var))),
                  enumerable: s(:true),
                  configurable: s(:true)})
            end
          else
            # class method call
            s(:send, name, *m.children[1..-1])
          end

        elsif m.type == :block and m.children.first.children.first == nil
          # class method calls passing a block
          s(:block, s(:send, name, *m.children.first.children[1..-1]), 
            *m.children[1..-1])
        elsif [:send, :block].include? m.type
          # pass through method calls with non-nil targets
          m
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
          visible[m.children[1]] = name
          s(:send, name, "#{m.children[1]}=", *m.children[2..-1])
        elsif m.type == :alias
          s(:send, s(:attr, name, :prototype),
            "#{m.children[0].children.first}=", 
            s(:attr, s(:attr, name, :prototype), m.children[1].children.first))
        else
          raise NotImplementedError, "class #{ m.type }"
        end
      end

      body.flatten!

      # merge property definitions
      combine_properties(body)

      if inheritance
        body.unshift s(:send, name, :prototype=, 
          s(:send, s(:const, nil, :Object), :create, inheritance)),
          s(:send, s(:attr, name, :prototype), :constructor=, name)
      else
        body.compact!

        # look for first sequence of instance methods and properties
        methods = 0
        start = 0
        body.each do |node|
          if [:method, :prop].include? node.type and 
            node.children[0].type == :attr and
            node.children[0].children[1] == :prototype
            methods += 1
          elsif methods == 0
            start += 1
          else
            break
          end
        end

        # collapse sequence to a single assignment
        if methods > 1 or (methods == 1 and body[start].type == :prop)
          pairs = body[start...start+methods].map do |node|
            if node.type == :method
              s(:pair, s(:str, node.children[1].to_s.chomp('=')),
                node.children[2])
            else
              node.children[1].map {|prop, descriptor|
                s(:pair, s(:prop, prop), descriptor)}
            end
          end
          body[start...start+methods] =
            s(:send, name, :prototype=, s(:hash, *pairs.flatten))
        end
      end

      begin
        # save class name
        class_name, @class_name = @class_name, name
        class_parent, @class_parent = @class_parent, inheritance

        # inhibit ivar substitution within a class definition.  See ivars.rb
        ivars, self.ivars = self.ivars, nil

        # add locally visible interfaces to rbstack.  See send.rb, const.rb
        @rbstack.push visible

        parse s(:begin, s(:constructor, name, *init.children[1..-1]),
          *body.compact)
      ensure
        self.ivars = ivars
        @class_name = class_name
        @class_parent = class_parent
        @rbstack.pop
      end
    end

    # handle properties, methods, and constructors
    # @block_this and @block_depth are used by self
    # @instance_method is used by super and self
    handle :prop, :method, :constructor do |*args|
      begin
        instance_method, @instance_method = @instance_method, @ast
        @block_this, @block_depth = false, 0
        if @ast.type == :prop
          obj, props = *args
          if props.length == 1
            prop, descriptor = props.flatten
            parse s(:send, s(:const, nil, :Object), :defineProperty,
              obj, s(:sym, prop), s(:hash,
              *descriptor.map { |key, value| s(:pair, s(:sym, key), value) }))
          else
            parse s(:send, s(:const, nil, :Object), :defineProperties,
              obj, s(:hash, *props.map {|prop, descriptor|
                s(:pair, s(:sym, prop), s(:hash, *descriptor.map {|key, value| 
                s(:pair, s(:sym, key), value) }))}))
          end
        elsif @ast.type == :method
          parse s(:send, *args)
        elsif args.first.children.first
          parse s(:send, args.first.children.first,
            "#{args.first.children[1]}=", s(:block, s(:send, nil, :proc), 
            *args[1..-1]))
        else
          parse s(:def, args.first.children[1], *args[1..-1])
        end
      ensure
        @instance_method = instance_method
        @block_this, @block_depth = nil, nil
      end
    end
  end
end
