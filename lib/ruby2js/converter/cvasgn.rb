module Ruby2JS
  class Converter

    # (cvasgn :@@a
    #   (int 1))

    handle :cvasgn do |var, expression=nil|
      multi_assign_declarations if @state == :statement

      if @class_name
        parse @class_name
        put var.to_s.sub('@@', "._")
      elsif @prototype
        put var.to_s.sub('@@', 'this._')
      else
        put var.to_s.sub('@@', 'this.constructor._')
      end

      if expression
        put " = "; parse expression
      end
    end
  end
end
