module Ruby2JS
  class Converter

    # (zsuper)
    # 
    # (super ...)

    handle :super, :zsuper do |*args|
      unless @class_parent and @instance_method
        raise NotImplementedError, "super outside of a method"
      end

      # what to pass
      if @ast.type == :zsuper
        if @instance_method.type == :method
          args = @instance_method.children[2].children[1].children
        elsif @instance_method.type == :prop
          args = nil
        else
          args = @instance_method.children[1].children
        end
      end

      parse @class_parent

      # what to call
      if @instance_method.type != :constructor
        puts  ".prototype.#{ @instance_method.children[1].to_s.chomp('=') }"
      end

      if args
        put '.call('; parse_all s(:self), *args, join: ', '; put ')'
      end
    end
  end
end
