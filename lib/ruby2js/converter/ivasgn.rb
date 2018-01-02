module Ruby2JS
  class Converter

    # (ivasgn :@a
    #   (int 1))

    handle :ivasgn do |var, expression=nil|
      put "#{ var.to_s.sub('@', 'this._') }"
      if expression
        put " = "; parse expression
      end
    end
  end
end
