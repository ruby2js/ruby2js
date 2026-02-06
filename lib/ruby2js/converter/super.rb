module Ruby2JS
  class Converter

    # (zsuper)
    # 
    # (super ...)

    handle :super, :zsuper do |*args|
      method = @instance_method || @class_method

      # If no class parent (e.g., in a module/concern), emit undefined
      # to avoid empty expressions like "return  || foo" becoming syntax errors
      unless @class_parent
        put 'undefined'
        return
      end

      # Require method context when we have a class parent
      unless method
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

      add_args = true

      if @class_method
        put 'super.'
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
    end
  end
end
