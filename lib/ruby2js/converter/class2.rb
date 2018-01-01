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
      put " {"

      body.compact!
      while body.length == 1 and body.first.type == :begin
        body = body.first.children 
      end

      body.each_with_index do |m, index|
        put(index == 0 ? @nl : @sep)

        if m.type == :def
          @prop = m.children.first

          if @prop == :initialize
            @prop = :constructor 
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
          end
        end
      end

      put "#@nl}"
    end
  end
end
