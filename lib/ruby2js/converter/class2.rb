module Ruby2JS
  class Converter

    # (class2
    #   (const nil :A)
    #   (const nil :B)
    #   (...)

    # NOTE: this is the es2015 version of class

    handle :class2 do |name, inheritance, *body|
      if name.type == :const and name.children.first == nil
        put 'class '
        parse name
      else
        parse name
        put ' = class'
      end

      if inheritance
        put ' extends '
        parse inheritance
      end

      put " {"

      body.compact!
      while body.length == 1 and body.first.type == :begin
        body = body.first.children 
      end

      begin
        class_name, @class_name = @class_name, name
        class_parent, @class_parent = @class_parent, inheritance
        @rbstack.push({})

        # capture method names for automatic self referencing
        body.each_with_index do |m, index|
          if m.type == :def
            prop = m.children.first
            unless prop == :initialize or prop.to_s.end_with? '='
              @rbstack.last[prop] = s(:self)
            end
          end
        end

        post = []
        skipped = false
        body.each_with_index do |m, index|
          put(index == 0 ? @nl : @sep) unless skipped
          comments = comments(m)
          location = output_location
          skipped = false

          # intercept async definitions
          if es2017 and m.type == :send and m.children[0..1] == [nil, :async]
            child = m.children[2]
            if child.type == :def
              m = child.updated(:async)
            elsif child.type == :defs and child.children[0].type == :self
              m = child.updated(:asyncs)
            end
          end

          if m.type == :def || m.type == :async
            @prop = m.children.first

            if @prop == :initialize
              @prop = :constructor 
              m = m.updated(m.type, [@prop, *m.children[1..2]])
            elsif not m.is_method?
              @prop = "get #{@prop}"
              m = m.updated(m.type, [*m.children[0..1], 
                s(:autoreturn, m.children[2])])
            elsif @prop.to_s.end_with? '='
              @prop = @prop.to_s.sub('=', '').to_sym
              m = m.updated(m.type, [@prop, *m.children[1..2]])
              @prop = "set #{@prop}"
            elsif @prop.to_s.end_with? '!'
              @prop = @prop.to_s.sub('!', '')
              m = m.updated(m.type, [@prop, *m.children[1..2]])
            end

            begin
              @instance_method = m
              parse m
            ensure
              @instance_method = nil
            end

          elsif 
            [:defs, :asyncs].include? m.type and m.children.first.type == :self
          then

            @prop = "static #{m.children[1]}"
            if not m.is_method?
              @prop = "static get #{m.children[1]}"
              m = m.updated(m.type, [*m.children[0..2], 
                s(:autoreturn, m.children[3])])
            elsif @prop.to_s.end_with? '='
              @prop = "static set #{m.children[1].to_s.sub('=', '')}"
            elsif @prop.to_s.end_with? '!'
              m = m.updated(m.type, [m.children[0],
                m.children[1].to_s.sub('!', ''), *m.children[2..3]])
              @prop = "static #{m.children[1]}"
            end

            @prop.sub! 'static', 'static async' if m.type == :asyncs

            m = m.updated(:def, m.children[1..3])
            parse m

          elsif m.type == :send and m.children.first == nil
            if m.children[1] == :attr_accessor
              m.children[2..-1].each_with_index do |child_sym, index2|
                put @sep unless index2 == 0
                var = child_sym.children.first
                put "get #{var}() {#{@nl}return this._#{var}#@nl}#@sep"
                put "set #{var}(#{var}) {#{@nl}this._#{var} = #{var}#@nl}"
              end
            elsif m.children[1] == :attr_reader
              m.children[2..-1].each_with_index do |child_sym, index2|
                put @sep unless index2 == 0
                var = child_sym.children.first
                put "get #{var}() {#{@nl}return this._#{var}#@nl}"
              end
            elsif m.children[1] == :attr_writer
              m.children[2..-1].each_with_index do |child_sym, index2|
                put @sep unless index2 == 0
                var = child_sym.children.first
                put "set #{var}(#{var}) {#{@nl}this._#{var} = #{var}#@nl}"
              end
            elsif [:private, :protected, :public].include? m.children[1]
              raise Error.new("class #{m.children[1]} is not supported", @ast)
            else
              if m.children[1] == :include
                m = m.updated(:begin, m.children[2..-1].map {|mname|
                  s(:send, s(:const, nil, :Object), :assign,
                  s(:attr, name, :prototype), mname)})
              end

              skipped = true
            end

          else
            skipped = true

            if m.type == :casgn and m.children[0] == nil
              @rbstack.last[m.children[1]] = name
            elsif m.type == :alias
              @rbstack.last[m.children[0]] = name
            end
          end

          if skipped
            post << [m, comments] if skipped
          else
            comments.reverse.each {|comment| insert location, comment}
          end
        end

        put @nl unless skipped
        put '}'

        post.each do |m, comments|
          put @sep
          comments.each {|comment| put comment}
          if m.type == :alias
            parse name
            put '.prototype.'
            put m.children[0].children[0]
            put ' = '
            parse name
            put '.prototype.'
            put m.children[1].children[0]
          elsif m.type == :class
            innerclass_name = m.children.first
            if innerclass_name.children.first
              innerclass_name = innerclass_name.updated(nil,
                [s(:attr, innerclass_name.children[0], name),
                 innerclass_name.children[1]])
            else
              innerclass_name = innerclass_name.updated(nil,
                [name, innerclass_name.children[1]])
            end
            parse m.updated(nil, [innerclass_name, *m.children[1..-1]])
          else
            parse m, :statement
          end
        end

      ensure
        @class_name = class_name
        @class_parent = class_parent
        @rbstack.pop
      end
    end
  end
end
