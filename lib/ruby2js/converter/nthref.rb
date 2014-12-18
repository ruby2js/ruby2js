module Ruby2JS
  class Converter

    # (nthref 1)

    handle :nth_ref do |var|
      "$#{var}"
    end
  end
end
