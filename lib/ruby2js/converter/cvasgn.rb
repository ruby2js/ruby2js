module Ruby2JS
  class Converter

    # (cvasgn :@@a
    #   (int 1))

    handle :cvasgn do |var, expression=nil|
      multi_assign_declarations if @state == :statement

      prefix = es2020 ? '#$' : '_'

      if @class_name
        parse @class_name
        put var.to_s.sub('@@', ".#{prefix}")
      elsif @prototype
        put var.to_s.sub('@@', "this.#{prefix}")
      else
        put var.to_s.sub('@@', "this.constructor.#{prefix}")
      end

      if expression
        put " = "; parse expression
      end
    end
  end
end
