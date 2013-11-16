module Ruby2JS
  class Converter

    # (and-asgn
    #   (lvasgn :a
    #   (int 1))

    handle :and_asgn do |var, value|
      "#{ parse var } = #{parse var} && #{ parse value }"
    end
  end
end
