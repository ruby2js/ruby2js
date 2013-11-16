module Ruby2JS
  class Converter

    # (return
    #   (int 1))

    handle :return do |value=nil|
      if value
        "return #{ parse value }"
      else
        "return"
      end
    end
  end
end
