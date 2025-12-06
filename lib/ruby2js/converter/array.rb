module Ruby2JS
  class Converter

    # (array
    #   (int 1)
    #   (int 2))

    handle :array do |*items|
      splat = items.rindex { |a| a.type == :splat }
      if splat and items.length == 1
        item = items[splat].children.first
        parse item
      else
        if items.length <= 1
          put '['; parse_all(*items, join: ', '); put ']'
        else
          compact { puts '['; parse_all(*items, join: ",#{@ws}"); sput ']' }
        end
      end
    end
  end
end
