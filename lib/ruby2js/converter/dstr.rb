module Ruby2JS
  class Converter

    # (dstr
    #   (str 'a')
    #   (...))

    # (dsym
    #   (str 'a')
    #   (...))

    handle :dstr, :dsym do |*children|
      children.each_with_index do |child, index|
        put ' + ' unless index == 0

        if child.type == :begin and child.children.length == 1
          child = child.children.first
        end

        if child.type == :send
          op_index = operator_index child.children[1]
          if op_index >= operator_index(:+)
            group child
          else
            parse child
          end
        else
          parse child
        end
      end
    end
  end
end
