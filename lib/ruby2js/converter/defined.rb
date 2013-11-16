module Ruby2JS
  class Converter

    # (defined? :@a)

    # (undefined? :@a)

    # NOTE: undefined is not produced directly by Parser

    handle :defined?, :undefined? do |var|
      op = (@ast.type == :defined? ? "!==" : "===")
      "typeof #{ parse var } #{ op } 'undefined'"
    end
  end
end
