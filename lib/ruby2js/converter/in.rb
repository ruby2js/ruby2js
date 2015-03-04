module Ruby2JS
  class Converter

    # (prototype expr) 

    # NOTE: in? is a synthetic 

    handle :in? do |left, right|
      "#{ parse left } in #{ parse right }"
    end
  end
end
