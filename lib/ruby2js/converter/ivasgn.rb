module Ruby2JS
  class Converter

    # (ivasgn :@a
    #   (int 1))

    handle :ivasgn do |var, expression|
      "#{ var.to_s.sub('@', 'this._') } = #{ parse expression }"
    end
  end
end
