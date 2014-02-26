module Ruby2JS
  class Converter

    # (zsuper)
    # 
    # (super ...)

    handle :super, :zsuper do |*args|
      unless @class_parent and @instance_method
        raise NotImplementedError, "super outside of a method"
      end

      # what to call
      if @instance_method.type == :method
        method = ".prototype.#{ @instance_method.children[1].to_s.chomp('=') }"
      else
        method = ''
      end

      # what to pass
      if @ast.type == :zsuper
        if @instance_method.type == :method
          args = @instance_method.children[2].children[1].children
        else
          args = @instance_method.children[1].children
        end
      end

      args = [s(:self), *args].map {|arg| parse arg}.join(', ')
      "#{ parse @class_parent }#{ method }.call(#{ args })"
    end
  end
end
