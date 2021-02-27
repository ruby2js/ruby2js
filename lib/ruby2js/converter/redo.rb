module Ruby2JS
  class Converter

    # (redo)

    handle :redo do
      unless @redoable and @next_token == :continue
        raise Error.new("redo outside of loop", @ast)
      end

      put "redo$ = true#{@sep}continue"
    end
  end
end
