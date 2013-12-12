module Ruby2JS
  class Converter

    # (cvasgn :@@a
    #   (int 1))

    handle :cvasgn do |var, expression=nil|
      if @prototype
        var = var.to_s.sub('@@', 'this._')
      elsif @class_name
        var = var.to_s.sub('@@', "#{parse @class_name}._")
      else
        var = var.to_s.sub('@@', 'this.constructor._')
      end

      if expression
        "#{ var } = #{ parse expression }"
      else
        var
      end
    end
  end
end
