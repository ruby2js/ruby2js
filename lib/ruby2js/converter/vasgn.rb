module Ruby2JS
  class Converter

    # (lvasgn :a
    #   (int 1))

    # (gvasgn :$a
    #   (int 1))

    handle :lvasgn, :gvasgn do |name, value=nil|
      state  = @state
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
              *undecls.map {|uname| s(:lvasgn, uname)}, @ast), @state
          end
        end

        if state == :statement and @scope and not @vars.include?(name) 
          if es2015
            var = 'let '
          else
            var = 'var ' 
          end
        end

        if value
          put "#{ var }#{ name } = "; parse value
        else
          put "#{ var }#{ name }"
        end
      ensure
        if @scope
          @vars[name] = true
        elsif state == :statement
          @vars[name] ||= :pending
        else
          @vars[name] ||= :implicit # console, document, ...
        end
      end
    end
  end
end
