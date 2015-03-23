module Ruby2JS
  class Converter

    # (undef
    #   (sym :foo)
    #   (sym :bar))

    handle :undef do |*syms|
      syms.each_with_index do |sym, index|
        put @sep unless index == 0

        if sym.type == :sym
          put "delete #{sym.children.last}"
        else
          put "delete "; parse sym
        end
      end
    end
  end
end
