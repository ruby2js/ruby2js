module Ruby2JS
  class Converter

    # (lvasgn :a
    #   (int 1))

    # (gvasgn :$a
    #   (int 1))

    handle :lvasgn, :gvasgn do |name, value=nil|
      begin
        if value and value.type == :lvasgn and @state == :statement
          undecls = []
          undecls << name unless @vars.include? name

          child = value
          while child and child.type == :lvasgn
            undecls << child.children[0] unless @vars.include? child.children[0]
            child = child.children[1]
          end

          unless undecls.empty?
            return parse s(:begin, 
              *undecls.map {|name| s(:lvasgn, name)}, @ast), @state
          end
        end

        var = 'var ' unless @vars.include?(name) or @state != :statement

        if value
          put "#{ var }#{ name } = "; parse value
        else
          put "#{ var }#{ name }"
        end
      ensure
        @vars[name] = true
      end
    end
  end
end
