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
        add_args = true

        if @class_method
          parse @class_parent
          put '.'
          put method.children[0]
          add_args = method.is_method?
        elsif method.children[0] == :constructor
          put 'super'
        else
          put 'super.'
          put method.children[0]
          add_args = method.is_method?
        end

        if add_args
          put '('
          cleaned_args = args.map do |arg| # FIX: #212
            arg.type == :optarg ? s(:arg, arg.children[0]) : arg
          end
          parse s(:args, *cleaned_args)
          put ')'
        end
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
