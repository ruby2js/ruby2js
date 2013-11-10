require 'parser/current'

module Ruby2JS
  class Converter
    LOGICAL   = :and, :not, :or
    OPERATORS = [:[], :[]=], [:not, :!], [:*, :/, :%], [:+, :-], [:>>, :<<], 
      [:<=, :<, :>, :>=], [:==, :!=], [:and, :or]
    
    attr_accessor :method_calls

    def initialize( ast, vars = {} )
      @ast, @vars = ast, vars.dup
      @sep = '; '
      @nl = ''
      @method_calls = [:toString]
    end
    
    def enable_vertical_whitespace
      @sep = ";\n"
      @nl = "\n"
    end

    def to_js
      parse( @ast )
    end

    def operator_index op
      OPERATORS.index( OPERATORS.find{ |el| el.include? op } ) || -1
    end
    
    def scope( ast )
      frame = self.class.new( nil, @vars )
      frame.enable_vertical_whitespace if @nl == "\n"
      frame.method_calls = @method_calls
      frame.parse( ast )
    end

    def s(type, *args)
      Parser::AST::Node.new(type, args)
    end

    def parse ast
      return ast unless Parser::AST::Node === ast

      case ast.type
        
      when :int, :float, :str
        ast.children.first.inspect

      when :sym
        ast.children.first.to_s.inspect

      when :lvar, :gvar
        mutate_name ast.children.first
        
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
        "#{ parse var } #{ op }= #{ parse value }"

      when :casgn
        cbase, var, value = ast.children
        var = mutate_name var
        var = "#{cbase}.var" if cbase
        output = "const #{ var } = #{ parse value }"
        @vars[var] = true
        output
        
      when :gvasgn
        name, value = ast.children
        "#{ mutate_name(name).sub('$', '') } = #{ parse value }"
        
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
          "#{parse left} : #{parse right}"
        end
        "{#{ hashy.join(', ') }}"

      when :array
        list = ast.children.map { |a| parse a }
        if list.join(', ').length < 80
          "[#{ list.join(', ') }]"
        else
          "[\n#{ list.join(",\n") }\n]"
        end

      when :begin
        ast.children.map{ |e| parse e }.join(@sep)
        
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
    
      when :send
        receiver, method, *args = ast.children
        if method == :new and receiver and receiver.children == [nil, :Proc]
          return parse args.first
        elsif method == :lambda and not receiver
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

        when :call
          "#{ parse receiver }(#{ parse args.first })"

        when :to_i
          "ParseInt(#{ parse receiver })"

        when :to_f
          "ParseFloat(#{ parse receiver })"

        when :[]
          raise 'parse error' unless receiver
          "#{ parse receiver }[#{ parse args.first }]"
          
        when :attr_accessor
          args = args.map do |arg|
            name = arg.children.last
            parse( s(:def, name, name) ).sub(/return null(\s*\})\z/, 
              "if (name) {this._#{ name } = name} else {return this._#{ name }}\\1")
          end.join(@sep)
          
        when *OPERATORS.flatten
          method = method_name_substitution method
          "#{ group_receiver ? group(receiver) : parse(receiver) } #{ method } #{ group_target ? group(target) : parse(target) }"  

        when /=$/
          "#{ parse receiver }#{ '.' if receiver }#{ method.to_s.sub(/=$/, ' =') } #{ parse args.first }"

        else
          method = method_name_substitution method
          if args.length == 0 and not @method_calls.include? method
            "#{ parse receiver }#{ '.' if receiver }#{ method }"
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
        output = "if (#{ parse condition }) {#@nl#{ scope true_block }#@nl}"
        while else_block and else_block.type == :if
          condition, true_block, else_block = else_block.children
          output <<  " else if (#{ parse condition }) {#@nl#{ scope true_block }#@nl}"
        end
        output << " else {#@nl#{ scope else_block }#@nl}" if else_block
        output
        
      when :while
        condition, block = ast.children
        "while (#{ parse condition }) {#@nl#{ scope block }#@nl}"

      when :block
        call, args, block = ast.children
        block ||= s(:nil)
        function = s(:def, name, args, block)
        parse s(:send, *call.children, function)
      
      when :def
        name, args, body = ast.children
        body ||= s(:nil)
        body   = s(:scope, body) unless body.type == :scope
        body   = parse body
        body.sub! /return var (\w+) = ([^;]+)\z/, "var \\1 = \\2#{@sep}return \\1"
        "function#{ " #{name}" if name }(#{ parse args }) {#@nl#{ body }#@nl}"

      when :scope
        body = ast.children.first
        body = s(:begin, body) unless body.type == :begin
        block = body.children
        unless block.last.type == :return
          children = block.dup
          children.push s(:return, children.pop)
          body = s(:begin, *children)
        end
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
        ast.children.map { |a| a.children.first }.join(', ')
        
      when :dstr
        ast.children.map{ |s| parse s }.join(' + ')
        
      when :self
        'this'

      else 
        raise "unknown AST type #{ ast.type }"
      end
    end
    
    SUBSTITUTIONS = Hash.new().merge({ 
      # :array => {
        :size     => :length,
        :<<       => :+,
        :index    => 'indexOf',
        :rindex   => 'lastIndexOf',
        :any?     => 'some',
        :all?     => 'every',
        :find_all => 'filter',
        :each_with_index => 'each',
      # },
      #     :* => {
        :to_a => :toArray,
        :to_s => :toString,
      #     }
    })
    
    def method_name_substitution method
      SUBSTITUTIONS[ method ] || method
    end
    
    def group( ast )
      "(#{ parse ast })"
    end
    
    def mutate_name( name )
      if name == :$$
        '$'
      else
        name.to_s
      end
    end
  end
end
