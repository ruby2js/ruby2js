module Ruby2JS
  class Converter

    # (ivar :@a)

    handle :ivar do |var|
      var.to_s.sub('@', 'this._')
    end
  end
end
