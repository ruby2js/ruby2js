module Ruby2JS
  class Converter

    # (defined? :@a)

    # (undefined? :@a)

    # NOTE: undefined is not produced directly by Parser

    handle :defined?, :undefined? do |var|
      op = (@ast.type == :defined? ? :"!==" : :===)
      put "typeof "; parse var; put " #{ op } 'undefined'"
    end
  end
end
