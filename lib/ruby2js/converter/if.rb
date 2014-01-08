module Ruby2JS
  class Converter

    # (if
    #   (true)
    #   (...)
    #   (...))

    handle :if do |condition, then_block, else_block|
      # return parse not condition if else_block and no then_block
      if else_block and not then_block
        return parse(s(:if, s(:not, condition), else_block, nil), @state) 
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
