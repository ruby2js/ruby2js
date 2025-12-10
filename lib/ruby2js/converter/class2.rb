module Ruby2JS
  class Converter

    # (class2
    #   (const nil :A)
    #   (const nil :B)
    #   (...)

    # NOTE: this is the ES2015+ class handler

    handle :class2 do |name, inheritance, *body|
      body.compact!
      while body.length == 1 and body.first.type == :begin
        body = body.first.children
      end

      # Flatten any nested :begin nodes in the body
      # (e.g., from multi-type handle blocks in selfhost filter)
      body = body.flat_map do |m|
        m&.type == :begin ? m.children : m
      end.compact

      proxied = body.find do |node| 
        node.type == :def and node.children.first == :method_missing
      end

      if not name
        put 'class'
      elsif name.type == :const and name.children.first == nil
        put 'class '
        parse name
        put '$' if proxied
      else
        parse name
        put '$' if proxied
        put ' = class'
      end

      if inheritance
        put ' extends '
        parse inheritance
      end

      put " {"

      begin
        class_name, @class_name = @class_name, name
        class_parent, @class_parent = @class_parent, inheritance
        @rbstack.push(@namespace.getOwnProps)
        @rbstack.last.merge!(@namespace.find(inheritance)) if inheritance
        constructor = []
        index = 0

        # capture constructor, method names for automatic self referencing
        body.each do |m|
          if m.type == :def
            prop = m.children.first
            if prop == :initialize and !@rbstack.last[:initialize]
              constructor = m.children[2..-1]
            elsif prop.to_s.end_with? '='
              @rbstack.last[prop.to_s[0..-2].to_sym] = s(:autobind, s(:self))
            else
              # Store both symbol and string-without-suffix versions of the method name
              # to match how send.rb looks up methods:
              # - For regular methods (no ?/!), send.rb looks up by symbol
              # - For ?/! methods, send.rb strips suffix and looks up by string
              @rbstack.last[prop] = m.is_method? ? s(:autobind, s(:self)) : s(:self)
              if prop.to_s =~ /[?!]$/
                key = prop.to_s.sub(/[?!]$/, '')
                @rbstack.last[key] = m.is_method? ? s(:autobind, s(:self)) : s(:self)
              end
            end
          elsif m.type == :send and m.children[0..1] == [nil, :async]
            if m.children[2].type == :def
              prop = m.children[2].children.first
              @rbstack.last[prop] = s(:autobind, s(:self))
              if prop.to_s =~ /[?!]$/
                key = prop.to_s.sub(/[?!]$/, '')
                @rbstack.last[key] = s(:autobind, s(:self))
              end
            end
          end
        end

        # private variable declarations
        unless underscored_private
          ivars = Set.new
          cvars = Set.new

          # find ivars and cvars
          walk = proc do |ast|
            ivars << ast.children.first if ast.type === :ivar
            ivars << ast.children.first if ast.type === :ivasgn
            cvars << ast.children.first if ast.type === :cvar
            cvars << ast.children.first if ast.type === :cvasgn

            ast.children.each do |child|
              walk.call(child) if ast_node?(child)
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
          walk.call(@ast)

          while constructor.length == 1 and constructor.first.type == :begin
            constructor = constructor.first.children.dup # Pragma: array
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

          # process leading initializers in constructor
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
          node_comments = comments(m)
          location = output_location
          skipped = false

          # intercept async definitions
          if m.type == :send and m.children[0..1] == [nil, :async]
            child = m.children[2]
            if child.type == :def
              m = child.updated(:async)
            elsif child.type == :defs and child.children[0].type == :self
              m = child.updated(:asyncs)
            end
          end

          if %i[def defm deff async].include? m.type
            @prop = m.children.first

            if @prop == :initialize and !@rbstack.last[:initialize]
              @prop = :constructor 

              if constructor == [] or constructor == [(:super)]
                skipped = true 
                next
              end

              m = m.updated(m.type, [@prop, m.children[1], s(:begin, *constructor)])
            elsif not m.is_method? and !%i[defm deff].include?(m.type)
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
            elsif @prop.to_s.end_with? '?'
              @prop = @prop.to_s.sub('?', '')
              m = m.updated(m.type, [@prop, *m.children[1..2]])
            end

            begin
              @instance_method = m
              @class_method = nil
              parse m # unless skipped
            ensure
              @instance_method = nil
            end

          elsif \
            [:defs, :defp, :asyncs].include? m.type and m.children.first.type == :self
          then

            @prop = "static #{m.children[1]}"
            if m.type == :defp or not m.is_method?
              @prop = "static get #{m.children[1]}"
              m = m.updated(m.type, [*m.children[0..2], 
                s(:autoreturn, m.children[3])])
            elsif @prop.to_s.end_with? '='
              @prop = "static set #{m.children[1].to_s.sub('=', '')}"
            elsif @prop.to_s.end_with? '!'
              m = m.updated(m.type, [m.children[0],
                m.children[1].to_s.sub('!', ''), *m.children[2..3]])
              @prop = "static #{m.children[1]}"
            elsif @prop.to_s.end_with? '?'
              m = m.updated(m.type, [m.children[0],
                m.children[1].to_s.sub('?', ''), *m.children[2..3]])
              @prop = "static #{m.children[1]}"
            end

            @prop = @prop.sub('static', 'static async') if m.type == :asyncs

            m = m.updated(:def, m.children[1..3])
            begin
              @instance_method = nil
              @class_method = m
              parse m # unless skipped
            ensure
              @instance_method = nil
            end

          elsif m.type == :send and m.children.first == nil
            p = underscored_private ? '_' : '#'

            if m.children[1] == :attr_accessor
              m.children[2..-1].each_with_index do |child_sym, index2|
                put @sep unless index2 == 0
                var = child_sym.children.first
                @rbstack.last[var] = s(:self)
                put "get #{var}() {#{@nl}return this.#{p}#{var}#@nl}#@sep"
                put "set #{var}(#{var}) {#{@nl}this.#{p}#{var} = #{var}#@nl}"
              end
            elsif m.children[1] == :attr_reader
              m.children[2..-1].each_with_index do |child_sym, index2|
                put @sep unless index2 == 0
                var = child_sym.children.first
                @rbstack.last[var] = s(:self)
                put "get #{var}() {#{@nl}return this.#{p}#{var}#@nl}"
              end
            elsif m.children[1] == :attr_writer
              m.children[2..-1].each_with_index do |child_sym, index2|
                put @sep unless index2 == 0
                var = child_sym.children.first
                @rbstack.last[var] = s(:self)
                put "set #{var}(#{var}) {#{@nl}this.#{p}#{var} = #{var}#@nl}"
              end
            elsif [:private, :protected, :public].include? m.children[1]
              raise Error.new("class #{m.children[1]} is not supported", @ast)
            else
              if m.children[1] == :include
                m = m.updated(:begin, m.children[2..-1].map {|mname|
                  @namespace.defineProps @namespace.find(mname)
                  s(:assign, s(:attr, name, :prototype), mname)
                })
              end

              skipped = true
            end

          elsif es2022 and \
            m.type == :send and m.children.first.type == :self and \
            m.children[1].to_s.end_with? '='

            put 'static '
            parse m.updated(:lvasgn, [m.children[1].to_s.sub('=', ''),
              m.children[2]])

          elsif m.type == :defineProps
            skipped = true
            @namespace.defineProps m.children.first
            @rbstack.last.merge! m.children.first

          else
            if m.type == :cvasgn and !underscored_private
              put 'static #$'; put m.children[0].to_s[2..-1]; put ' = '
              parse m.children[1]
            else
              skipped = true
            end

            if m.type == :casgn and m.children[0] == nil
              @rbstack.last[m.children[1]] = name

              if es2022
                put 'static '; put m.children[1].to_s; put ' = '
                parse m.children[2]
                skipped = false
              end
            elsif m.type == :alias
              @rbstack.last[m.children[0]] = name
            end
          end

          if skipped
            post << [m, node_comments] unless m.type == :defineProps
          else
            (node_comments || []).reverse.each {|comment| insert location, comment}
          end
        end

        put @nl unless skipped
        put '}'

        post.each do |m, m_comments|
          put @sep
          m_comments.each {|comment| put comment}
          if m.type == :alias
            parse name
            put '.prototype.'
            put m.children[0].children[0].to_s.sub(/[?!]$/, '')
            put ' = '
            parse name
            put '.prototype.'
            put m.children[1].children[0].to_s.sub(/[?!]$/, '')
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
          elsif m.type == :send && (m.children[0].nil? || m.children[0].type == :self)
            if m.children[0].nil?
              parse m.updated(:send, [@class_name, *m.children[1..-1]])
            else
              parse m.updated(:send, [@class_name, *m.children[1..-1]])
            end
          elsif m.type == :block and m.children.first.children.first == nil
            # class method calls passing a block
            parse s(:block, s(:send, name, *m.children.first.children[1..-1]), 
              *m.children[1..-1])
          else
            parse m, :statement
          end
        end

        if proxied
          put @sep

          rename = name.updated(nil, [name.children.first, name.children.last.to_s + '$'])

          if proxied.children[1].children.length == 1
            # special case: if method_missing only has on argument, call it
            # directly (i.e., don't pass arguments).  This enables
            # method_missing to return instance attributes (getters) as well
            # as bound functions (methods).
            forward = s(:send, s(:lvar, :obj), :method_missing, s(:lvar, :prop))
          else
            # normal case: return a function which, when called, will call
            # method_missing with method name and arguments.
            forward = s(:block, s(:send, nil, :proc), s(:args, s(:restarg, :args)),
            s(:send, s(:lvar, :obj), :method_missing, s(:lvar, :prop),
            s(:splat, s(:lvar, :args))))
          end

          proxy = s(:return, s(:send, s(:const, nil, :Proxy), :new,
            s(:send, rename, :new, s(:splat, s(:lvar, :args))),
            s(:hash, s(:pair, s(:sym, :get), s(:block, s(:send, nil, :proc),
            s(:args, s(:arg, :obj), s(:arg, :prop)),
            s(:if, s(:in?, s(:lvar, :prop), s(:lvar, :obj)),
            s(:return, s(:send, s(:lvar, :obj), :[], s(:lvar, :prop))),
            s(:return, forward))))))
          )

          if name.children.first == nil
            proxy = s(:def, name.children.last, s(:args, s(:restarg, :args)), proxy)
          else
            proxy = s(:defs, *name.children, s(:args, s(:restarg, :args)), proxy)
          end

          parse proxy
        end

      ensure
        @class_name = class_name
        @class_parent = class_parent
        @namespace.defineProps @rbstack.pop
      end
    end
  end
end
