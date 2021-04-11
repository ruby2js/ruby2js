module Ruby2JS
  class Converter
    handle :match_pattern do |value, name|
      parse @ast.updated(:lvasgn, [name.children.first, value]), @state
    end
  end
end
