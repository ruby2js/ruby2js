module Ruby2JS
  class Converter

    # (hash
    #   (pair
    #     (sym :name)
    #     (str "value")))

    handle :hash do |*pairs|
      pairs.map! do |node|
        left, right = node.children
        key = parse left
        key = $1 if key =~ /\A"([a-zA-Z_$][a-zA-Z_$0-9]*)"\Z/
        "#{key}: #{parse right}"
      end
      "{#{ pairs.join(', ') }}"
    end
  end
end
