module Ruby2JS
  class Converter

    # (cvar :@@a)

    handle :cvar do |var|
      if @prototype
        var.to_s.sub('@@', 'this._')
      elsif @class_name
        var.to_s.sub('@@', "#{parse @class_name}._")
      else
        var.to_s.sub('@@', 'this.constructor._')
      end
    end
  end
end
