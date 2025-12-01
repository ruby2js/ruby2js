module Ruby2JS
  class Converter

    # (op-asgn
    #   (lvasgn :a) :+
    #   (int 1))

    # NOTE: and-asgn and or_asgn handled below

    handle :op_asgn do |var, op, value|
      var = s(:ivar, var.children.first) if var.type == :ivasgn
      var = s(:lvar, var.children.first) if var.type == :lvasgn
      var = s(:cvar, var.children.first) if var.type == :cvasgn

      if var.type == :lvar
        name = var.children.first
        receiver = @rbstack.map {|rb| rb[name]}.compact.last
        if receiver
          var = s(:attr, nil, name)
        end
      end

      if \
        [:+, :-].include?(op) and value.type==:int and 
        (value.children==[1] or value.children==[-1])
      then
        if value.children.first == -1
          op = (op == :+ ? :- : :+)
        end

        if @state == :statement
          parse var; put "#{ op }#{ op }"
        else
          put "#{ op }#{ op }"; parse var
        end
      else
        parse var; put " #{ op }= "; parse value
      end
    end

    # (or-asgn
    #   (lvasgn :a)
    #   (int 1))

    # (and-asgn
    #   (lvasgn :a)
    #   (int 1))

    handle :or_asgn, :and_asgn do |asgn, value|
      type = (@ast.type == :and_asgn ? :and : :or)

      vtype = nil
      vtype = :lvar if asgn.type == :lvasgn
      vtype = :ivar if asgn.type == :ivasgn
      vtype = :cvar if asgn.type == :cvasgn

      # With truthy option, expand to full assignment using truthy helpers
      if @truthy && vtype
        # a ||= b  =>  a = $ror(a, () => b)
        # a &&= b  =>  a = $rand(a, () => b)
        @need_truthy_helpers << :T
        helper = type == :or ? :ror : :rand
        @need_truthy_helpers << helper
        parse s(asgn.type, asgn.children.first,
          s(:send, nil, :"$#{helper}",
            s(vtype, asgn.children.first),
            s(:block, s(:send, nil, :lambda), s(:args), value)))
        return
      end

      if es2021 && !@truthy
        op = type == :and ? '&&' : (@or == :nullish ? '??' : '||')
        parse s(:op_asgn, asgn, op, value);
      elsif vtype
        parse s(asgn.type, asgn.children.first, s(type,
          s(vtype, asgn.children.first), value))
      elsif asgn.type == :send and asgn.children[1] == :[]
        parse s(:send, asgn.children.first, :[]=,
          asgn.children[2], s(type, asgn, value))
      else
        parse s(:send, asgn.children.first, "#{asgn.children[1]}=",
          s(type, asgn, value))
      end
    end
  end
end
