module Ruby2JS
  class Converter

    # (dstr
    #   (str 'a')
    #   (...))

    # (dsym
    #   (str 'a')
    #   (...))

    handle :dstr, :dsym do |*children|
      children.map! do |child| 
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

      children.join(' + ')
    end
  end
end
