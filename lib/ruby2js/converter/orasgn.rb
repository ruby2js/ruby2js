module Ruby2JS
  class Converter

    # (or-asgn
    #   (lvasgn :a
    #   (int 1))

    handle :or_asgn do |var, value|
      "#{ parse var } = #{parse var} || #{ parse value }"
    end
  end
end
