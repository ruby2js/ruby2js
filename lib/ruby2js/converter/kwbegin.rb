module Ruby2JS
  class Converter

    # (kwbegin
    #   (ensure
    #     (rescue
    #      (send nil :a)
    #      (resbody nil nil
    #        (send nil :b)) nil)
    #    (send nil :c)))

    handle :kwbegin do |*children|
      block = children.first
      if block.type == :ensure
        block, finally = block.children
      else
        finally = nil
      end

      if block and block.type == :rescue
        body, recover, otherwise = block.children
        raise NotImplementedError, "block else" if otherwise
        exception, name, recovery = recover.children
        raise NotImplementedError, parse(exception) if exception
      else
        body = block
      end

      output = "try {#@nl#{ parse body }#@nl}"

      if recovery
        output += " catch (#{ parse name }) {#@nl#{ parse recovery }#@nl}"
      end

      output += " finally {#@nl#{ parse finally }#@nl}" if finally

      if recovery or finally
        output
      else
        parse s(:begin, *children)
      end
    end
  end
end
