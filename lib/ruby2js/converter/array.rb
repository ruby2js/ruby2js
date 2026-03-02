module Ruby2JS
  class Converter

    # (array
    #   (int 1)
    #   (int 2))

    handle :array do |*items|
      # Sentinel: s(:array, s(:cast, expr)) marks expr as array-typed
      # without adding literal brackets — just emit the inner expression.
      if items.length == 1 && items.first.type == :cast
        parse items.first
        next
      end

      splat = items.rindex { |a| a.type == :splat }
      if splat
        # Array contains splat - must use [...x] syntax to preserve copy semantics
        # [*x] in Ruby creates a new array, so we need [...x] in JS
        if items.length <= 1
          put '['; parse_all(*items, join: ', '); put ']'
        else
          self._compact { puts '['; parse_all(*items, join: ",#{@ws}"); sput ']' }
        end
      else
        if items.length <= 1
          put '['; parse_all(*items, join: ', '); put ']'
        else
          self._compact { puts '['; parse_all(*items, join: ",#{@ws}"); sput ']' }
        end
      end
    end
  end
end
