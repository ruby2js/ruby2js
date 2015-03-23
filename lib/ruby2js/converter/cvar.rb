module Ruby2JS
  class Converter

    # (cvar :@@a)

    handle :cvar do |var|
      if @class_name
        parse @class_name
        put var.to_s.sub('@@', "._")
      elsif @prototype
        put var.to_s.sub('@@', 'this._')
      else
        put var.to_s.sub('@@', 'this.constructor._')
      end
    end
  end
end
