module Ruby2JS
  class Converter

    # (undef
    #   (sym :foo)
    #   (sym :bar))

    handle :undef do |*syms|
      syms.map {|sym| "delete #{sym.children.last}"}.join @sep
    end
  end
end
