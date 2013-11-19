module Ruby2JS
  class Converter

    # (case
    #   (send nil :a)
    #   (when
    #      (int 1)
    #      (...))
    #   (...))

    handle :case do |expr, *whens, other|
      whens.map! do |node|
        *values, code = node.children
        cases = values.map {|value| "case #{ parse value }:#@ws"}.join
        "#{ cases }#{ parse code, :statement }#{@sep}break#@sep"
      end

      other = "#{@nl}default:#@ws#{ parse other, :statement }#@nl" if other

      "switch (#{ parse expr }) {#@nl#{whens.join(@nl)}#{other}}"
    end
  end
end
