module Ruby2JS
  class Converter

    # (zsuper)
    # 
    # (super ...)

    handle :super, :zsuper do |*args|
      method = @instance_method || @class_method

      unless method and @class_parent
        raise Error.new("super outside of a method", @ast)
      end

      # what to pass
      if @ast.type == :zsuper
        if method.type == :method
          args = method.children[2].children[1].children
        elsif method.type == :prop
          args = nil
        else
          args = method.children[1].children
        end
      end

      if es2015
        if @class_method
          parse @class_parent
          put '.'
          put method.children[0]
        elsif method.children[0] == :constructor
          put 'super'
        else
          put 'super.'
          put method.children[0]
        end

        put '('
        parse s(:args, *args)
        put ')'
      else
        parse @class_parent

        # what to call
        if method.type != :constructor
          puts  ".prototype.#{ method.children[1].to_s.chomp('=') }"
        end

        if args
          put '.call('; parse_all s(:self), *args, join: ', '; put ')'
        end
      end
    end
  end
end
