require 'parser/current'

module Ruby2JS
  class Converter
    LOGICAL   = :and, :not, :or
    OPERATORS = [:[], :[]=], [:not, :!], [:*, :/, :%], [:+, :-], [:>>, :<<], 
      [:<=, :<, :>, :>=], [:==, :!=, :===], [:and, :or]
    
    def initialize( ast, vars = {} )
      @ast, @vars = ast, vars.dup
      @sep = '; '
      @nl = ''
    end
    
    def enable_vertical_whitespace
      @sep = ";\n"
      @nl = "\n"
    end

    def to_js
      parse( @ast, :statement )
    end

    def operator_index op
      OPERATORS.index( OPERATORS.find{ |el| el.include? op } ) || -1
    end
    
    def scope( ast )
      frame = self.class.new( nil, @vars )
      frame.enable_vertical_whitespace if @nl == "\n"
      frame.parse( ast, :statement )
    end

    def s(type, *args)
      Parser::AST::Node.new(type, args)
    end

    def is_method?(node)
      return false unless node.type == :send
      return true unless node.loc
      selector = node.loc.selector
      return true unless selector.source_buffer
      selector.source_buffer.source[selector.end_pos] == '('
    end

    def parse(ast, state=:expression)
      return ast unless Parser::AST::Node === ast

      case ast.type
        
      when :int, :float, :str
        ast.children.first.inspect

      when :sym
        ast.children.first.to_s.inspect

      when :lvar, :gvar, :cvar
        ast.children.first
        
      when :true, :false
        ast.type.to_s
        
      when :nil
        'null'

      when :lvasgn
        var, value = ast.children
        output      = value ? "#{ 'var ' unless @vars.keys.include? var }#{ var } = #{ parse value }" : var
        @vars[var] = true
        output

      when :op_asgn
        var, op, value = ast.children

        if [:+, :-].include?(op) and value.type==:int and value.children==[1]
          if state == :statement
            "#{ parse var }#{ op }#{ op }"
          else
            "#{ op }#{ op }#{ parse var }"
          end
        else
          "#{ parse var } #{ op }= #{ parse value }"
        end

      when :casgn
        cbase, var, value = ast.children
        var = "#{cbase}.var" if cbase
        output = "const #{ var } = #{ parse value }"
        @vars[var] = true
        output
        
      when :gvasgn
        name, value = ast.children
        "#{ name } = #{ parse value }"
        
      when :ivasgn
        name, expression = ast.children
        "#{ name.to_s.sub('@', 'this._') } = #{ parse expression }"
        
      when :or_asgn
        var, value = ast.children
        "#{ parse var } = #{parse var} || #{ parse value }"

      when :and_asgn
        var, value = ast.children
        "#{ parse var } = #{parse var} && #{ parse value }"
        
      when :ivar
        name = ast.children.first
        name.to_s.sub('@', 'this._')
        
      when :hash
        hashy  = ast.children.map do |node|
          left, right = node.children
          key = parse left
          key = $1 if key =~ /\A"([a-zA-Z_$][a-zA-Z_$0-9]*)"\Z/
          "#{key}: #{parse right}"
        end
        "{#{ hashy.join(', ') }}"

      when :regexp
        str, opt = ast.children
        if str.children.first.include? '/'
          if opt.children.empty?
            "new RegExp(#{ str.children.first.inspect })"
          else
            "new RegExp(#{ str.children.first.inspect }, #{ opt.children.join.inspect})"
          end
        else
          "/#{ str.children.first }/#{ opt.children.join }"
        end

      when :array
        splat = ast.children.rindex { |a| a.type == :splat }
        if splat
          items = ast.children
          item = items[splat].children.first
          if items.length == 1
            parse item
          elsif splat == items.length - 1
            parse s(:send, s(:array, *items[0..-2]), :concat, item)
          elsif splat == 0
            parse s(:send, item, :concat, s(:array, *items[1..-1]))
          else
            parse s(:send, 
              s(:send, s(:array, *items[0..splat-1]), :concat, item), 
              :concat, s(:array, *items[splat+1..-1]))
          end
        else
          list = ast.children.map { |a| parse a }
          if list.join(', ').length < 80
            "[#{ list.join(', ') }]"
          else
            "[\n#{ list.join(",\n") }\n]"
          end
        end

      when :begin
        ast.children.map{ |e| parse e, :statement }.join(@sep)
        
      when :return
        "return #{ parse ast.children.first }"
        
      when *LOGICAL
        left, right = ast.children
        left = left.children.first if left and left.type == :begin
        right = right.children.first if right.type == :begin
        op_index    = operator_index ast.type
        lgroup      = LOGICAL.include?( left.type ) && op_index <= operator_index( left.type )
        left        = parse left
        left        = "(#{ left })" if lgroup
        rgroup      = LOGICAL.include?( right.type ) && op_index <= operator_index( right.type ) if right.children.length > 0
        right       = parse right
        right       = "(#{ right })" if rgroup

        case ast.type
        when :and
          "#{ left } && #{ right }"
        when :or
          "#{ left } || #{ right }"
        else
          "!#{ left }"
        end
    
      when :send, :attr
        receiver, method, *args = ast.children
        if method == :new and receiver and receiver.children == [nil, :Proc]
          return parse args.first
        elsif not receiver and [:lambda, :proc].include? method
          return parse args.first
        end

        op_index   = operator_index method
        if op_index != -1
          target = args.first 
          target = target.children.first if target and target.type == :begin
          receiver = receiver.children.first if receiver.type == :begin
        end

        group_receiver = receiver.type == :send && op_index <= operator_index( receiver.children[1] ) if receiver
        group_target = target.type == :send && op_index <= operator_index( target.children[1] ) if target

        case method
        when :!
          group_receiver ||= (receiver.children.length > 1)
          "!#{ group_receiver ? group(receiver) : parse(receiver) }"

        when :[]
          raise 'parse error' unless receiver
          "#{ parse receiver }[#{ parse args.first }]"

        when :-@, :+@
          "#{ method.to_s[0] }#{ parse receiver }"

        when :=~
          "#{ parse args.first }.test(#{ parse receiver })"

        when :!~
          "!#{ parse args.first }.test(#{ parse receiver })"

        when *OPERATORS.flatten
          "#{ group_receiver ? group(receiver) : parse(receiver) } #{ method } #{ group_target ? group(target) : parse(target) }"  

        when /=$/
          "#{ parse receiver }#{ '.' if receiver }#{ method.to_s.sub(/=$/, ' =') } #{ parse args.first }"

        when :new
          args = args.map {|a| parse a}.join(', ')
          "new #{ parse receiver }(#{ args })"

        else
          if args.length == 0 and not is_method?(ast)
            "#{ parse receiver }#{ '.' if receiver }#{ method }"
          elsif args.length > 0 and args.last.type == :splat
            parse s(:send, s(:attr, receiver, method), :apply, receiver, 
              s(:send, s(:array, *args[0..-2]), :concat,
                args[-1].children.first))
          else
            args = args.map {|a| parse a}.join(', ')
            "#{ parse receiver }#{ '.' if receiver }#{ method }(#{ args })"
          end
        end
        
      when :const
        receiver, name = ast.children
        "#{ parse receiver }#{ '.' if receiver }#{ name }"

      when :masgn
        lhs, rhs = ast.children
        block = []
        lhs.children.zip rhs.children.zip do |var, val| 
          block << s(var.type, *var.children, *val)
        end
        parse s(:begin, *block)
      
      when :if
        condition, true_block, else_block = ast.children
        if state == :statement
          output = "if (#{ parse condition }) {#@nl#{ scope true_block }#@nl}"
          while else_block and else_block.type == :if
            condition, true_block, else_block = else_block.children
            output <<  " else if (#{ parse condition }) {#@nl#{ scope true_block }#@nl}"
          end
          output << " else {#@nl#{ scope else_block }#@nl}" if else_block
          output
        else
          "(#{ parse condition } ? #{ parse true_block } : #{ parse else_block })"
        end
        
      when :while
        condition, block = ast.children
        "while (#{ parse condition }) {#@nl#{ scope block }#@nl}"

      when :for
        var, expression, block = ast.children
        parse s(:block, 
          s(:send, expression, :forEach),
          s(:args, s(:arg, var.children.last)),
          block);

      when :block
        call, args, block = ast.children
        block ||= s(:begin)
        function = s(:def, name, args, block)
        parse s(:send, *call.children, function)
      
      when :def
        name, args, body = ast.children
        body ||= s(:begin)
        if args and !args.children.empty? and args.children.last.type == :restarg
          if args.children[-1].children.first
            body = s(:begin, body) unless body.type == :begin
            slice = s(:attr, s(:attr, s(:const, nil, :Array), :prototype), :slice)
            call = s(:send, slice, :call, s(:lvar, :arguments),
              s(:int, args.children.length-1))
            assign = s(:lvasgn, args.children[-1].children.first, call)
            body = s(:begin, assign, *body.children)
          end
          args = s(:args, *args.children[0..-2])
        end
        body   = s(:scope, body) unless body.type == :scope
        body   = parse body
        "function#{ " #{name}" if name }(#{ parse args }) {#@nl#{ body }#@nl}"

      when :scope
        body = ast.children.first
        body = s(:begin, body) unless body.type == :begin
        block = body.children
        scope body
        
      when :class
        name, inheritance, *body = ast.children
        body.compact!
        body = body.first.children.dup if body.length == 1 and body.first.type == :begin
        methods = body.select { |a| a.type == :def }
        init    = (body.delete methods.find { |m| m.children.first == :initialize }) || s(:def, :initialize)
        block   = body.collect { |m| parse( m ).sub(/function (\w+)/, "#{ parse name }.prototype.\\1 = function") }.join @sep
        "#{ parse( s(:def, parse(name), init.children[1], init.children[2]) ).sub(/return (?:null|(.*))\}\z/, '\1}') }#{ @sep if block and not block.empty?}#{ block }"

      when :args
        ast.children.map { |a| parse a }.join(', ')

      when :arg, :blockarg
        ast.children.first

      when :block_pass
        parse ast.children.first
        
      when :dstr, :dsym
        ast.children.map{ |s| parse s }.join(' + ')
        
      when :self
        'this'

      when :break
        'break'

      when :next
        'continue'

      when :defined?
        "typeof #{ parse ast.children.first } === 'undefined'"

      when :undef
        ast.children.map {|c| "delete #{c.children.last}"}.join @sep

      else 
        raise NotImplementedError, "unknown AST type #{ ast.type }"
      end
    end
    
    def group( ast )
      "(#{ parse ast })"
    end
  end
end
