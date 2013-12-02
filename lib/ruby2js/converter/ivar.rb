module Ruby2JS
  class Converter

    # (ivar :@a)

    handle :ivar do |var|
      if self.ivars and self.ivars.include? var
        Ruby2JS.convert(self.ivars[var].inspect)
      else
        var.to_s.sub('@', 'this._')
      end
    end
  end
end
