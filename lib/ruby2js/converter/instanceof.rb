module Ruby2JS
  class Converter

    # (instanceof target class)
    # Generates: target instanceof ClassName

    # NOTE: instanceof is a synthetic node type

    handle :instanceof do |target, klass|
      parse target; put " instanceof "; parse klass
    end
  end
end
