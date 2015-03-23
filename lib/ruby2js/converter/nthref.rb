module Ruby2JS
  class Converter

    # (nthref 1)

    handle :nth_ref do |var|
      put "$#{var}"
    end
  end
end
