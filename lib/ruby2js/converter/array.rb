module Ruby2JS
  class Converter

    # (array
    #   (int 1)
    #   (int 2))

    handle :array do |*items|
      splat = items.rindex { |a| a.type == :splat }
      if splat
        item = items[splat].children.first
        if items.length == 1
          parse item
        elsif splat == items.length - 1
          parse s(:send, s(:array, *items[0..-2]), :concat, item)
        elsif splat == 0
          parse s(:send, item, :concat, s(:array, *items[1..-1]))
        else
          parse s(:send, 
            s(:send, s(:array, *items[0..splat-1]), :concat, item), 
            :concat, s(:array, *items[splat+1..-1]))
        end
      else
        if items.length <= 1
          # TODO items.map {|item| item.length+2}.reduce(&:+).to_i < @width-8
          put '['; parse_all *items, join: ', '; put ']'
        else
          compact { puts '['; parse_all *items, join: ",#{@ws}"; sput ']' }
        end
      end
    end
  end
end
