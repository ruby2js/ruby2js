module Ruby2JS
  class Converter
    handle :match_pattern do |value, name|
      if name.type == :match_var
        parse @ast.updated(:lvasgn, [name.children.first, value]), @state
      elsif name.type == :hash_pattern and name.children.all? {|child| child.type == :match_var}
        put 'let { '
        put name.children.map {|child| child.children[0].to_s}.join(', ')
        put ' } = '
        parse value
      else
        raise Error.new("complex match patterns are not supported", @ast)
      end
    end
  end
end
