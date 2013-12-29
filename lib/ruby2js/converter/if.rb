module Ruby2JS
  class Converter

    # (if
    #   (true)
    #   (...)
    #   (...))

    INVERT_OP = {
      :<  => :>=,
      :<= => :>,
      :== => :!=,
      :!= => :==,
      :>  => :<=,
      :>= => :<
    }

    handle :if do |condition, then_block, else_block|
      # return parse condition if not else_block and not then_block
      if else_block and not then_block
        if condition.type == :send and INVERT_OP.include? condition.children[1]
          return parse(s(:if, s(:send, condition.children[0],
            INVERT_OP[condition.children[1]], condition.children[2]),
            else_block,nil), @state) 
        else
          return parse(s(:if, s(:send, condition, :!), else_block, nil), @state) 
        end
      end

      then_block ||= s(:nil)

      if @state == :statement
        output = "if (#{ parse condition }) {#@nl#{ scope then_block }#@nl}"
        while else_block and else_block.type == :if
          condition, then_block, else_block = else_block.children
          output <<  " else if (#{ parse condition }) " +
            "{#@nl#{ scope then_block }#@nl}"
        end
        output << " else {#@nl#{ scope else_block }#@nl}" if else_block

        # use short form when appropriate
        unless output.length>@width-8 or else_block or then_block.type == :begin
          output = "if (#{ parse condition }) #{ scope then_block }"
        end

        output
      else
        "(#{ parse condition } ? #{ parse then_block } : #{ parse else_block })"
      end
    end
  end
end
