module Ruby2JS
  class Converter

    # (block
    #   (send nil :x)
    #   (args
    #     (arg :a))
    #   (lvar :a))

    handle :block do |call, args, block|

      # Handle Ruby 3.4 `it` implicit block parameter
      # When args is nil and block uses `it`, convert to explicit parameter
      if args.nil?
        uses_it = false
        walk = proc do |node|
          next unless ast_node?(node)
          if node.type == :lvar && node.children.first == :it
            uses_it = true
          else
            node.children.each { |child| walk.call(child) }
          end
        end
        walk.call(block)
        args = uses_it ? s(:args, s(:arg, :it)) : s(:args)
      end

      # Check for trailing `async` arg in block call: `it "works", async do end`
      # Using element-wise comparison for selfhost JS compatibility
      last_arg = call.children.last
      is_async_arg = last_arg.respond_to?(:type) &&
                     last_arg.type == :send &&
                     last_arg.children[0] == nil &&
                     last_arg.children[1] == :async &&
                     last_arg.children.length == 2
      if is_async_arg
        return parse call.updated(nil, [*call.children[0..-2],
        s(:send, nil, :async, s(:block, s(:send, nil, :proc), args, block))])
      end

      if \
        @state == :statement and args.children.length == 1 and
        call.children.first and call.children.first.type == :begin and
        call.children[1] == :step and
        [:irange, :erange].include? call.children.first.children.first.type
      then
        begin
          vars = @vars.dup # Pragma: hash
          next_token, @next_token = @next_token, :continue

          # convert combinations of range, step and block to a for loop
          var = args.children.first
          expression = call.children.first.children.first
          comp = (expression.type == :irange ? '<=' : '<')
          put "for (let "; 
          parse var; put " = "; parse expression.children.first
          put "; "; parse var; 
          if call.children[2].type == :int and call.children[2].children[0] < 0
            put " #{comp.sub('<', '>')} "; parse expression.children.last
            put "; "; parse s(:op_asgn, var, :-, 
              s(:int, -call.children[2].children[0])), :statement
          else
            put " #{comp} "; parse expression.children.last
            put "; "; parse s(:op_asgn, var, :+, call.children[2]), :statement
          end
          puts ") {"
          scope block
          sput "}"
        ensure
          @next_token = next_token
          @vars = vars
        end

      elsif \
        call.children[0] == nil and call.children[1] == :loop and
        args.children.length == 0
      then
        # Ruby's `loop do ... end` → `while (true) { ... }`
        # Handle `break value` by rewriting to temp var assignment + break
        has_break_value = false
        rewrite_break = proc do |node|
          next node unless ast_node?(node)
          if node.type == :break && node.children.length > 0 && node.children[0]
            has_break_value = true
            s(:begin,
              s(:lvasgn, :_loop_result, node.children[0]),
              s(:break))
          else
            new_children = node.children.map { |c|
              ast_node?(c) ? rewrite_break.call(c) : c
            }
            node.updated(nil, new_children)
          end
        end

        rewritten_block = rewrite_break.call(block || s(:begin))

        if has_break_value && @state != :statement
          # Used as an expression: wrap in IIFE
          put '(() => { let _loop_result; '
          begin
            vars = @vars.dup # Pragma: hash
            @vars[:_loop_result] = true
            next_token, @next_token = @next_token, :continue
            puts 'while (true) {'
            scope rewritten_block
            sput '}'
          ensure
            @next_token = next_token
            @vars = vars
          end
          put ' return _loop_result})()'
        else
          begin
            vars = @vars.dup # Pragma: hash
            if has_break_value
              put 'let _loop_result; '
              @vars[:_loop_result] = true
            end
            next_token, @next_token = @next_token, :continue
            puts 'while (true) {'
            scope rewritten_block
            sput '}'
            if has_break_value
              put '; _loop_result'
            end
          ensure
            @next_token = next_token
            @vars = vars
          end
        end

      elsif \
        call.children[0] == nil and call.children[1] == :function and
        call.children[2..-1].all? do |child|
          # In Ruby, method names are Symbols. In JS (selfhosted), they're strings.
          # Using respond_to? pattern to work in both: check it's not a complex node
          child.type == :lvar or (child.type == :send and
            child.children.length == 2 and child.children[0] == nil and
            !child.children[1].respond_to?(:type))
        end
      then
        # accommodate javascript style syntax: convert function blocks with
        # simple arguments into an anonymous function
        args = call.children[2..-1].map {|arg| s(:arg, arg.children.last)}
        parse @ast.updated(:block, [s(:send, nil, :proc),
          s(:args, *args), block])

      else
        # convert blocks into method calls with an additional argument
        # consisting of an anonymous function
        block ||= s(:begin)
        function = @ast.updated(:def, [nil, args, block])
        parse s(call.type, *call.children, function), @state
      end
    end

    # (numblock
    #   (send nil :x)
    #   1
    #   (lvar :_1))

    handle :numblock do |call, count, block|
      parse s(:block,
        call,
        s(:args, *((1..count).map {|i| s(:arg, "_#{i}")})),
        block
      )
    end

  end
end
