module Ruby2JS
  class Converter

    # (hide, ...)

    handle :hide do |*nodes|
      capture {parse_all(*nodes)}

      @lines.pop if @state == :statement and @lines.last == []
      @lines.last.pop if @lines.last.last.to_s == @sep
    end
  end
end
