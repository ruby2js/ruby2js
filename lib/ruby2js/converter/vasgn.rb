module Ruby2JS
  class Converter

    # (lvasgn :a
    #   (int 1))

    # (gvasgn :$a
    #   (int 1))

    handle :lvasgn, :gvasgn do |var, value=nil|
      begin
        if value
          "#{ 'var ' unless @vars.include? var }#{ var } = #{ parse value }"
        else
          var
        end
      ensure
        @vars[var] = true
      end
    end
  end
end
