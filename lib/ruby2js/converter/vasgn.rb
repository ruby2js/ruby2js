module Ruby2JS
  class Converter

    # (lvasgn :a
    #   (int 1))

    # (gvasgn :$a
    #   (int 1))

    handle :lvasgn, :gvasgn do |name, value=nil|
      if @ast.type == :lvasgn and value
        # Only treat as setter if name is NOT already a local variable
        # and not marked as :masgn (from parallel assignment like `scope, @scope = ...`)
        # This handles cases where `scope` should be a new local var, not a call to self.scope=
        # Skip setter lookup if: already a real local var, or marked from parallel assignment
        # Additionally, only convert if the rbstack entry is a :setter (not a regular getter/method)
        unless @vars[name] == true || @vars[name] == :masgn
          receiver = @rbstack.map {|rb| rb[name]}.compact.last
          # Check if this is a setter marker (directly or wrapped in :private_method)
          is_setter = receiver&.type == :setter ||
            (receiver&.type == :private_method && receiver.children[1]&.type == :setter)
          if is_setter
            # Extract the actual receiver for parsing
            actual_receiver = receiver.type == :private_method ? receiver.children[1].children.first : receiver.children.first
            return parse s(:attr, actual_receiver, "#{name}=", value)
          end
        end
      end

      state  = @state
      begin
        if value and value.type == :lvasgn and @state == :statement
          undecls = []
          undecls << name unless @vars.key?(name)

          child = value
          while child and child.type == :lvasgn
            undecls << child.children[0] unless @vars.key?(child.children[0])
            child = child.children[1]
          end

          unless undecls.empty?
            put 'let '
            put undecls.map(&:to_s).join(', ') + @sep
            undecls.each {|var| @vars[var] = true}
          end
        end

        hoist = false
        # Treat :masgn marker as "not yet declared" for purposes of adding let/var
        is_declared = @vars.key?(name) && @vars[name] != :masgn
        if state == :statement and not is_declared
          hoist = hoist?(@scope, @inner, name) if @inner and @scope != @inner
          if not hoist
            var = 'let '
          end
        end

        if value
          put "#{ var }#{ jsvar(name) } = "; parse value
        else
          put "#{ var }#{ jsvar(name) }"
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
        return true if ast_node?(var) && hoist?(var, inner, name)
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

        if child.type == :lvasgn and not @vars.key?(child.children[0])
          undecls << child.children[0]
        end
      end

      unless undecls.empty?
        put "let "
        put "#{undecls.map(&:to_s).join(', ')}#@sep"
      end
    end
  end
end
