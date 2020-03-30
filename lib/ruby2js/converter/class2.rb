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
        constructor = []
        index = 0

        # capture constructor, method names for automatic self referencing
        body.each do |m|
          if m.type == :def
            prop = m.children.first
            if prop == :initialize
              constructor = m.children[2..-1]
            elsif not prop.to_s.end_with? '='
              @rbstack.last[prop] = s(:self)
            end
          end
        end

        # private variable declarations
        if es2020
          ivars = Set.new
          cvars = Set.new

          # find ivars and cvars
          walk = proc do |ast|
            ivars << ast.children.first if ast.type === :ivar
            ivars << ast.children.first if ast.type === :ivasgn
            cvars << ast.children.first if ast.type === :cvar
            cvars << ast.children.first if ast.type === :cvasgn

            ast.children.each do |child|
              walk[child] if child.is_a? Parser::AST::Node
            end

	    if ast.type == :send and ast.children.first == nil
	      if ast.children[1] == :attr_accessor
		ast.children[2..-1].each_with_index do |child_sym, index2|
		  ivars << :"@#{child_sym.children.first}"
		end
	      elsif ast.children[1] == :attr_reader
		ast.children[2..-1].each_with_index do |child_sym, index2|
		  ivars << :"@#{child_sym.children.first}"
		end
	      elsif ast.children[1] == :attr_writer
		ast.children[2..-1].each_with_index do |child_sym, index2|
		  ivars << :"@#{child_sym.children.first}"
		end
	      end
	    end

          end
          walk[@ast]

          # process leading initializers in constructor
          while constructor.length == 1 and constructor.first.type == :begin
            constructor = constructor.first.children.dup
          end

          # emit additional class declarations
          unless cvars.empty?
            body.each do |m|
              cvars.delete m.children.first if m.type == :cvasgn
            end
          end
          cvars.to_a.sort.each do |cvar|
            put(index == 0 ? @nl : @sep)
            index += 1
            put 'static #$' + cvar.to_s[2..-1]
          end

          while constructor.length > 0 and constructor.first.type == :ivasgn
            put(index == 0 ? @nl : @sep)
            index += 1
            statement = constructor.shift
            put '#'
            put statement.children.first.to_s[1..-1]
            put ' = '
            parse statement.children.last

            ivars.delete statement.children.first
          end

          # emit additional instance declarations
          ivars.to_a.sort.each do |ivar|
            put(index == 0 ? @nl : @sep)
            index += 1
            put '#' + ivar.to_s[1..-1]
          end
        end

        # process class definition
        post = []
        skipped = false
        body.each do |m|
          put(index == 0 ? @nl : @sep) unless skipped
          index += 1
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

              if constructor == [] or constructor == [(:super)]
                skipped = true 
                next
              end

              m = m.updated(m.type, [@prop, m.children[1], s(:begin, *constructor)])
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
              @class_method = nil
              parse m # unless skipped
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
            begin
              @instance_method = nil
              @class_method = m
              parse m # unless skipped
            ensure
              @instance_method = nil
            end

          elsif m.type == :send and m.children.first == nil
            p = es2020 ? '#' : '_'

            if m.children[1] == :attr_accessor
              m.children[2..-1].each_with_index do |child_sym, index2|
                put @sep unless index2 == 0
                var = child_sym.children.first
                put "get #{var}() {#{@nl}return this.#{p}#{var}#@nl}#@sep"
                put "set #{var}(#{var}) {#{@nl}this.#{p}#{var} = #{var}#@nl}"
              end
            elsif m.children[1] == :attr_reader
              m.children[2..-1].each_with_index do |child_sym, index2|
                put @sep unless index2 == 0
                var = child_sym.children.first
                put "get #{var}() {#{@nl}return this.#{p}#{var}#@nl}"
              end
            elsif m.children[1] == :attr_writer
              m.children[2..-1].each_with_index do |child_sym, index2|
                put @sep unless index2 == 0
                var = child_sym.children.first
                put "set #{var}(#{var}) {#{@nl}this.#{p}#{var} = #{var}#@nl}"
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
            if m.type == :cvasgn and es2020
              put 'static #$'; put m.children[0].to_s[2..-1]; put ' = '
              parse m.children[1]
            else
              skipped = true
            end

            if m.type == :casgn and m.children[0] == nil
              @rbstack.last[m.children[1]] = name

              if es2020
                put 'static '; put m.children[1].to_s; put ' = '
                parse m.children[2]
                skipped = false
              end
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
