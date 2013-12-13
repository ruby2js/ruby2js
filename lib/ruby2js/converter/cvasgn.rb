module Ruby2JS
  class Converter

    # (cvasgn :@@a
    #   (int 1))

    handle :cvasgn do |var, expression=nil|
      if @class_name
        var = var.to_s.sub('@@', "#{parse @class_name}._")
      elsif @prototype
        var = var.to_s.sub('@@', 'this._')
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
