module Ruby2JS
  class Converter

    # (nthref 1)

    handle :nth_ref do |var|
      put "RegExp.$#{var}"
    end
  end
end
