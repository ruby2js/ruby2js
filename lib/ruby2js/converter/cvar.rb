module Ruby2JS
  class Converter

    # (cvar :@@a)

    handle :cvar do |var|
      if @class_name
        var.to_s.sub('@@', "#{parse @class_name}._")
      elsif @prototype
        var.to_s.sub('@@', 'this._')
      else
        var.to_s.sub('@@', 'this.constructor._')
      end
    end
  end
end
