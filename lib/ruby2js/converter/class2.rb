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

        post = []
        skipped = false
        body.each_with_index do |m, index|
          put(index == 0 ? @nl : @sep) unless skipped
          skipped = false

          if m.type == :def
            @prop = m.children.first

            if @prop == :initialize
              @prop = :constructor 
              m = m.updated(m.type, [@prop, *m.children[1..2]])
            elsif not m.is_method?
              @prop = "get #{@prop}"
              m = m.updated(m.type, [*m.children[0..1], 
                s(:autoreturn, m.children[2])])
            elsif @prop.to_s.end_with? '='
              @prop = "set #{@prop.to_s.sub('=', '')}"
              m = m.updated(m.type, [@prop, *m.children[1..2]])
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

          elsif m.type == :defs and m.children.first.type == :self
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

            m = m.updated(:def, m.children[1..3])
            parse m

          elsif m.type == :send and m.children.first == nil
            if m.children[1] == :attr_accessor
              m.children[2..-1].map do |child_sym|
                var = child_sym.children.first
                put "get #{var}() {#{@nl}return this._#{var}#@nl}#@sep"
                put "set #{var}(#{var}) {#{@nl}this._#{var} = #{var}#@nl}"
              end
            elsif m.children[1] == :attr_reader
              m.children[2..-1].map do |child_sym|
                var = child_sym.children.first
                put "get #{var}() {#{@nl}return this._#{var}#@nl}"
              end
            elsif m.children[1] == :attr_writer
              m.children[2..-1].map do |child_sym|
                var = child_sym.children.first
                put "set #{var}(#{var}) {#{@nl}this._#{var} = #{var}#@nl}"
              end
            else
              skipped = true
            end

          else
            post << m
            skipped = true
          end
        end

        put "#@nl}"

        post.each do |m|
          put @sep
          parse m, :statement
        end

      ensure
        @class_name = class_name
        @class_parent = class_parent
      end
    end
  end
end
