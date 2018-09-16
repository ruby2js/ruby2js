module Ruby2JS
  class Converter

    # (true)
    # (false)

    handle :__FILE__, :__LINE__ do
      put @ast.type.to_s
    end
  end
end
