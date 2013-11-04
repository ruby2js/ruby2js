require 'sexp_processor'
require 'ruby_parser'

class Ruby2JS
  VERSION   = '0.0.2'
  LOGICAL   = :and, :not, :or
  OPERATORS = [:[], :[]=], [:not, :!], [:*, :/, :%], [:+, :-, :<<], [:and], [:or]
  
  attr_accessor :method_calls

  def initialize( sexp, vars = {} )
    @sexp, @vars = sexp, vars.dup
    @sep = '; '
    @nl = ''
    @method_calls = []
  end
  
  def enable_vertical_whitespace
    @sep = ";\n"
    @nl = "\n"
  end

  def to_js
    parse( @sexp, nil )
  end

  def self.convert(string)
    ruby2js = Ruby2JS.new( RubyParser.new.parse( string ) )

    ruby2js.method_calls += string.scan(/(\w+)\(\)/).flatten.map(&:to_sym)

    if string.include? "\n"
      ruby2js.enable_vertical_whitespace 
      lines = ruby2js.to_js.split("\n")
      pre = ''
      pending = false
      blank = true
      lines.each do |line|
        if line.start_with? '}'
          pre.sub!(/^  /,'')
          line.sub!(/;$/,";\n")
          pending = true
        else
          pending = false
        end

        line.sub! /^/, pre
        if line.end_with? '{'
          pre += '  ' 
          line.sub!(/^/,"\n") unless blank or pending
        end

        blank = pending
      end
      lines.join("\n")
    else
      ruby2js.to_js
    end
  end
  
  protected
  def operator_index op
    OPERATORS.index( OPERATORS.find{ |el| el.include? op } ) || -1
  end
  
  def scope( sexp, vars, ancestor = nil )
    frame = self.class.new( nil, vars )
    frame.enable_vertical_whitespace if @nl == "\n"
    frame.method_calls = @method_calls
    frame.parse( sexp, ancestor )
  end

  def parse sexp, ancestor = nil
    return sexp unless sexp.kind_of? Array
    operand = sexp.shift

    case operand
      
    when :lit, :str
      lit = sexp.shift
      lit.is_a?( Numeric ) ? lit.to_s : lit.to_s.inspect
      
    when :lvar, :const
      sexp.shift.to_s
      
    when :true, :false
      operand.to_s
      
    when :nil
      'null'

    when :lasgn
      var         = mutate_name sexp.shift
      value       = sexp.shift
      val         = value.dup if value
      output      = value ? "#{ 'var ' unless @vars.keys.include? var }#{ var } = #{ parse value }" : var
      @vars[var] ||= []
      @vars[var] << (val && val.first == :lvar ? @vars[ val.last ] : val )
      output

    when :cdecl
      var         = mutate_name sexp.shift
      value       = sexp.shift
      val         = value.dup if value
      output      = "const #{ var } = #{ parse value }"
      @vars[var] ||= []
      @vars[var] << (val && val.first == :lvar ? @vars[ val.last ] : val )
      output
      
    when :gasgn
      "#{ mutate_name sexp.shift } = #{ parse sexp.shift }".sub('$', '')
      
    when :iasgn
      "#{ sexp.shift.to_s.sub('@', 'this._') } = #{ parse sexp.shift }"
      
    when :op_asgn_or
      var  = sexp.shift
      asgn = sexp.shift
      parse asgn.push( s(:or, var, asgn.pop) )
      
    when :ivar
      sexp.shift.to_s.sub('@', 'this._')
      
    when :hash
      hashy  = []
      hashy << [ parse( sexp.shift ), parse( sexp.shift ) ] until sexp.empty?
      "{#{ hashy.map{ |k,v| k << ' : ' << v }.join(',') }}"

    when :array
      "[#{ sexp.map{ |a| parse a }.join(', ') }]"

    when :block
      sexp.map{ |e| parse e }.join(@sep)
      
    when :return
      "return #{ parse sexp.shift }"
      
    when *LOGICAL
      left, right = sexp.shift, sexp.shift
      op_index    = operator_index operand
      lgroup      = LOGICAL.include?( left.first ) && op_index <= operator_index( left.first )
      left        = parse left
      left        = "(#{ left })" if lgroup
      rgroup      = LOGICAL.include?( right.first ) && op_index <= operator_index( right.first ) if right.length > 0
      right       = parse right
      right       = "(#{ right })" if rgroup

      case operand
      when :and
        "#{ left } && #{ right }"
      when :or
        "#{ left } || #{ right }"
      else
        "!#{ left }"
      end
  
    when :attrasgn
      receiver, attribute, expression = sexp.shift, sexp.shift, sexp.shift
      "#{ parse receiver }.#{ attribute.to_s.sub(/=$/,' = ')}#{ parse expression }"

    when :call
      receiver, method = sexp.shift, sexp.shift
      args = s(:arglist, *sexp)
      return parse args, :lambda if receiver == s(:const, :Proc) and method == :new or method == :lambda && !receiver
      op_index   = operator_index method
      target = sexp.first if op_index != -1
      group_receiver = receiver.first == :call && op_index <= operator_index( receiver[2] ) if receiver
      group_target = target.first == :call && op_index <= operator_index( target[2] ) if target

      case method
      when :!
        group_receiver ||= (receiver.length > 2)
        "!#{ group_receiver ? group(receiver) : parse(receiver) }"

      when :call
        "#{ parse receiver }(#{ parse args })"

      when :[]
        raise 'parse error' unless receiver
        "#{ parse receiver }[#{ parse args }]"
        
      when :attr_accessor
        args.shift
        args   = args.collect do |arg|
          name = arg.last
          parse( s(:defn, name, name) ).sub(/return null\}\z/, 
            "if (name) {this._#{ name } = name} else {return this._#{ name }}}")
        end.join(@sep)
        
      when *OPERATORS.flatten
        method = method_name_substitution receiver, method
        "#{ group_receiver ? group(receiver) : parse(receiver) } #{ method } #{ group_target ? group(args) : parse(args) }"  

      else
        method = method_name_substitution receiver, method
        if args.length == 1 and not @method_calls.include? method
          "#{ parse receiver }#{ '.' if receiver }#{ method }"
        else
          "#{ parse receiver }#{ '.' if receiver }#{ method }(#{ parse args })"
        end
      end
      
    when :arglist
      sexp.map{ |e| parse e }.join(', ')
      
    when :masgn
      if sexp.size == 1
        sexp    = sexp.shift
        sexp[0] = :arglist
        parse sexp
      else
        sexp.first[1..-1].zip sexp.last[1..-1] { |var, val| var << val }
        sexp = sexp.first
        sexp[0] = :block
        parse sexp
      end
    
    when :if
      condition    = parse sexp.shift
      true_block   = scope sexp.shift, @vars
      elseif       = parse sexp.find_node( :if, true ), :if
      else_block   = parse sexp.shift
      output       = "if (#{ condition }) {#@nl#{ true_block }#@nl}"
      output.sub!('if', 'else if') if ancestor == :if
      output << " #{ elseif }" if elseif
      output << " else {#@nl#{ else_block }#@nl}" if else_block
      output
      
    when :while
      condition    = parse sexp.shift
      block        = scope sexp.shift, @vars
      unknown      = parse sexp.shift
      "while (#{ condition }) {#@nl#{ block }#@nl}"

    when :iter
      caller       = sexp.shift
      args         = sexp.shift
      function     = s(:function, args, sexp.shift)
      caller.pop if caller.last == s(:arglist)
      caller      << function
      parse caller
    
    when :function
      args, body = sexp.shift, sexp.shift
      body ||= s(:nil)
      body   = s(:scope, body) unless body.first == :scope
      body   = parse body
      body.sub! /return var (\w+) = ([^;]+)\z/, "var \\1 = \\2#{@sep}return \\1"
      "function(#{ parse args }) {#@nl#{ body }#@nl}"
      
    when :defn
      name = sexp.shift
      sexp.unshift :function
      parse( sexp ).sub('function', "function #{ name }")
      
    when :scope
      body = sexp.shift
      body = s(:block, body) unless body.first == :block
      body.push s(:return, body.pop) unless body.last.first == :return
      body = scope body, @vars
      
    when :class
      name, inheritance, body = sexp.shift, sexp.shift, sexp
      methods = body.find_nodes(:defn) or s()
      init    = (body.delete methods.find { |m| m[1] == :initialize }) || []
      block   = body.collect { |m| parse( m ).sub(/function (\w+)/, "#{ name }.prototype.\\1 = function") }.join @sep
      "#{ parse( s(:defn, name, init[2], init[3]) ).sub(/return (?:null|(.*))\}\z/, '\1}') }#{ @sep if block and not block.empty?}#{ block }"

    when :args
      sexp.join(', ')
      
    when :dstr
      sexp.unshift s(:str, sexp.shift)
      sexp.collect{ |s| parse s }.join(' + ')
      
    when :evstr, :svalue
      parse sexp.shift

    when :self
      'this'

    else 
      raise "unknown operand #{ operand.inspect }"
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
      :to_a => 'toArray',
      :to_s => 'toString',
    #     }
  })
  
  def method_name_substitution receiver, method
    # if receiver
    #       receiver = last_original_assign receiver if receiver.first == :lvar
    #       receiver = receiver.flatten.first
    #     end
    # SUBSTITUTIONS[ :* ][ method ] || method || SUBSTITUTIONS[ receiver ][ method ] || method
    SUBSTITUTIONS[ method ] || method
  end
  
  def last_original_assign receiver
    ( @vars[ receiver.last ] || [] ).first || []
  end
  
  def group( sexp )
    "(#{ parse sexp })"
  end
  
  def mutate_name( name )
    name
  end

end
