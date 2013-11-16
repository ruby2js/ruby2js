module Ruby2JS
  class Converter

    # (op-asgn
    #   (lvasgn :a) :+
    #   (int 1))

    handle :op_asgn do |var, op, value|
      if [:+, :-].include?(op) and value.type==:int and value.children==[1]
        if @state == :statement
          "#{ parse var }#{ op }#{ op }"
        else
          "#{ op }#{ op }#{ parse var }"
        end
      else
        "#{ parse var } #{ op }= #{ parse value }"
      end
    end
  end
end
