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
            if es2015
              put 'let '
            else
              put 'var ' 
            end
            put undecls.map(&:to_s).join(', ') + @sep
            undecls.each {|var| @vars[var] = true}
          end
        end

        hoist = false
        if state == :statement and not @vars.include?(name) 
          hoist = hoist?(@scope, @inner, name) if @inner
          if not hoist
            if es2015
              var = 'let '
            else
              var = 'var '
            end
          end
        end

        if value
          put "#{ var }#{ name } = "; parse value
        else
          put "#{ var }#{ name }"
        end

        if not hoist
          @vars[name] ||= true
        elsif state == :statement
          @vars[name] ||= :pending
        else
          @vars[name] ||= :implicit # console, document, ...
        end
      end
    end

    # is 'name' referenced outside of inner scope?
    def hoist?(outer, inner, name)
      outer.children.each do |var|
        next if var == inner
        return true if var == name and [:lvar, :gvar].include? outer.type
        return true if Parser::AST::Node === var and hoist?(var, inner, name)
      end
      return false
    end

    def multi_assign_declarations
      undecls = []
      child = @ast
      loop do
        if [:send, :casgn].include? child.type
          subchild = child.children[2]
        else
          subchild = child.children[1]
        end

        if subchild.type == :send
          break unless subchild.children[1] =~ /=$/
        else
          break unless [:send, :cvasgn, :ivasgn, :gvasgn, :lvasgn].
            include? subchild.type
        end

        child = subchild

        if child.type == :lvasgn and not @vars.include?(child.children[0]) 
          undecls << child.children[0]
        end
      end

      unless undecls.empty?
        if es2015
          put "let "
        else
          put "var "
        end
        put "#{undecls.map(&:to_s).join(', ')}#@sep"
      end
    end
  end
end
