module Ruby2JS
  class Converter

    # (if
    #   (true)
    #   (...)
    #   (...))

    handle :if do |condition, then_block, else_block|
      # Pattern: a = b if a.nil?  =>  a ??= b (ES2021+)
      # Pattern: a.nil? ? b : a   =>  a ?? b  (ES2020+)
      if condition.type == :send and condition.children[1] == :nil? and
         condition.children[2..-1].empty?

        tested = condition.children[0]

        # Pattern: a = b if a.nil?  =>  a ??= b
        if es2021 and then_block and not else_block
          asgn = then_block
          if asgn.type == :lvasgn and tested.type == :lvar and
             asgn.children[0] == tested.children[0]
            # a = b if a.nil?  =>  a ??= b
            return parse s(:op_asgn, s(:lvasgn, tested.children[0]), '??', asgn.children[1])
          elsif asgn.type == :ivasgn and tested.type == :ivar and
                asgn.children[0] == tested.children[0]
            # @a = b if @a.nil?  =>  @a ??= b
            return parse s(:op_asgn, s(:ivasgn, tested.children[0]), '??', asgn.children[1])
          elsif asgn.type == :cvasgn and tested.type == :cvar and
                asgn.children[0] == tested.children[0]
            # @@a = b if @@a.nil?  =>  @@a ??= b
            return parse s(:op_asgn, s(:cvasgn, tested.children[0]), '??', asgn.children[1])
          elsif asgn.type == :send and asgn.children[1].to_s.end_with?('=') and
                asgn.children[1] != :[]= and
                tested.type == :send and
                asgn.children[0] == tested.children[0] and
                asgn.children[1].to_s.chomp('=') == tested.children[1].to_s
            # self.a = b if self.a.nil?  =>  self.a ??= b
            parse tested; put ' ??= '; parse asgn.children[2]
            return
          elsif asgn.type == :send and asgn.children[1] == :[]= and
                tested.type == :send and tested.children[1] == :[] and
                asgn.children[0] == tested.children[0] and
                asgn.children[2] == tested.children[2]
            # a[i] = b if a[i].nil?  =>  a[i] ??= b
            parse tested; put ' ??= '; parse asgn.children[3]
            return
          end
        end

        # Pattern: a.nil? ? b : a  =>  a ?? b
        if es2020 and then_block and else_block and else_block == tested
          parse tested; put ' ?? '; parse then_block
          return
        end
      end

      # return parse not condition if else_block and no then_block
      if else_block and not then_block
        return parse(s(:if, s(:not, condition), else_block, nil), @state)
      end

      then_block ||= s(:nil)

      if @state == :statement
        begin
          inner, @inner = @inner, @ast

          # use short form when appropriate
          unless else_block or then_block.type == :begin
            # "Lexical declaration cannot appear in a single-statement context"
            if [:lvasgn, :gvasgn].include? then_block.type
              @vars[then_block.children.first] ||= :pending
            end

            put "if ("
            saved_boolean_context, @boolean_context = @boolean_context, true
            parse condition
            @boolean_context = saved_boolean_context
            put ') '
            wrap { jscope then_block }
          else
            put "if ("
            saved_boolean_context, @boolean_context = @boolean_context, true
            parse condition
            @boolean_context = saved_boolean_context
            puts ') {'
            jscope then_block
            sput '}'

            while else_block and else_block.type == :if
              condition, then_block, else_block = else_block.children
              if then_block
                put ' else if ('
                saved_boolean_context, @boolean_context = @boolean_context, true
                parse condition
                @boolean_context = saved_boolean_context
                puts ') {'
                jscope then_block
                sput '}'
              else
                put ' else if ('
                saved_boolean_context, @boolean_context = @boolean_context, true
                parse s(:not, condition)
                @boolean_context = saved_boolean_context
                puts ') {'
                jscope else_block
                sput '}'
                else_block = nil
              end
            end

            if else_block
              puts ' else {'; jscope else_block; sput '}'
            end
          end
        ensure
          @inner = inner
        end
      else
        else_block ||= s(:nil)

        if @jsx
          if then_block.type == :begin
            then_block = s(:xnode, '', *then_block.children)
          end

          if else_block.type == :begin
            else_block = s(:xnode, '', *else_block.children)
          end
        else
          if then_block.type == :begin
            then_block = s(:kwbegin, then_block)
          end

          if else_block.type == :begin
            else_block = s(:kwbegin, else_block)
          end
        end

        saved_boolean_context, @boolean_context = @boolean_context, true
        parse condition
        @boolean_context = saved_boolean_context
        put ' ? '; parse then_block, @state
        put ' : '; parse else_block, @state
      end
    end
  end
end
