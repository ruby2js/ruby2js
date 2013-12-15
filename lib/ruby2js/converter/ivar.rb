module Ruby2JS
  class Converter

    # (ivar :@a)

    handle :ivar do |var|
      if self.ivars and self.ivars.include? var
        ruby2js = Ruby2JS::Converter.new(Ruby2JS.parse(self.ivars[var].inspect))
        ruby2js.width = @width
        ruby2js.enable_vertical_whitespace if @nl == "\n"
        ruby2js.to_js
      else
        var.to_s.sub('@', 'this._')
      end
    end
  end
end
