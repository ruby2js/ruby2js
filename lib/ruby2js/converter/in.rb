module Ruby2JS
  class Converter

    # (prototype expr) 

    # NOTE: in? is a synthetic 

    handle :in? do |left, right|
      parse left; put " in "; parse right
    end
  end
end
