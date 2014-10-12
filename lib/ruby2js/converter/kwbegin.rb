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
        body, *recovers, otherwise = block.children
        raise NotImplementedError, "block else" if otherwise

        if recovers.any? {|recover| not recover.children[1]}
          raise NotImplementedError, "recover without exception variable"
        end

        var = recovers.first.children[1]

        if recovers.any? {|recover| recover.children[1] != var}
          raise NotImplementedError, 
            "multiple recovers with different exception variables"
        end
      else
        body = block
      end

      output = "try {#@nl#{ parse body, :statement }#@nl}"

      if recovers
        if recovers.length == 1 and not recovers.first.children.first
          # single catch with no exception named
          output += " catch (#{ parse var }) " +
            "{#@nl#{ parse recovers.first.children.last, :statement }#@nl}"
        else
          output += " catch (#{ parse var }) {#@nl"

          first = true
          recovers.each do |recover|
            exceptions, var, recovery = recover.children

            if exceptions
              tests = exceptions.children.map do |exception|
                "#{ parse var} instanceof #{ parse exception }"
              end

              output += "} else " if not first
              first = false

              output += "if (#{ tests.join(' || ') }) {#@nl"
            else
              output += "} else {#@nl"
            end

            output += "#{ parse recovery, :statement }#@nl"
          end

          if recovers.last.children.first
            output += "} else {#{@nl}throw #{ parse var }#@nl"
          end

          output += "}#@nl}"
        end
      end

      output += " finally {#@nl#{ parse finally, :statement }#@nl}" if finally

      if recovers or finally
        output
      else
        parse s(:begin, *children)
      end
    end
  end
end
