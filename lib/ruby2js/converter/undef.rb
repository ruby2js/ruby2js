module Ruby2JS
  class Converter

    # (undef
    #   (sym :foo)
    #   (sym :bar))

    handle :undef do |*syms|
      "delete " + syms.
        map {|sym| sym.type == :sym ? sym.children.last : parse(sym)}.join(@sep)
    end
  end
end
