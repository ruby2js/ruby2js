require 'sexp_processor'

# $:.unshift(File.dirname(__FILE__)) unless $:.include?(File.dirname(__FILE__)) || $:.include?(File.expand_path(File.dirname(__FILE__)))

class Ruby2JS
  VERSION   = '0.0.2'
  LOGICAL   = :and, :not, :or
  OPERATORS = [:[], :[]=], [:not, :!], [:*, :/, :%], [:+, :-, :<<], [:and], [:or]
  
  def initialize( sexp, vars = {} )
    @sexp, @vars = sexp, vars.dup
  end
  
  def to_js
    parse( @sexp, nil )
  end
  
  protected
  def operator_index op
    OPERATORS.index( OPERATORS.find{ |el| el.include? op } ) || -1
  end
  
  def scope( sexp, vars, ancestor = nil )
    self.class.new( nil, vars ).parse( sexp, ancestor )
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
      sexp.map{ |e| parse e }.join('; ')
      
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

      when :[]
        raise 'parse error' unless receiver
        "#{ parse receiver }[#{ parse args }]"
        
      when :attr_accessor
        args.shift
        args   = args.collect do |arg|
          name = arg.last
          parse( s(:defn, name, name) ).sub(/return null\}\z/, "if (name) {self._#{ name } = name} else {self._#{ name }}}")
        end.join('; ')
        
      when *OPERATORS.flatten
        method = method_name_substitution receiver, method
        "#{ group_receiver ? group(receiver) : parse(receiver) } #{ method } #{ group_target ? group(args) : parse(args) }"  

      else
        method = method_name_substitution receiver, method
        "#{ parse receiver }#{ '.' if receiver }#{ method }(#{ parse args })"
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
      output       = "if (#{ condition }) {#{ true_block }}"
      output.sub!('if', 'else if') if ancestor == :if
      output << " #{ elseif }" if elseif
      output << " else {#{ else_block }}" if else_block
      output
      
    when :while
      condition    = parse sexp.shift
      block        = scope sexp.shift, @vars
      unknown      = parse sexp.shift
      "while (#{ condition }) {#{ block }}"

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
      body.sub!(/return var (\w+) = ([^;]+)\z/, 'var \1 = \2; return \1')
      "function(#{ parse args }) {#{ body }}"
      
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
      block   = body.collect { |m| parse( m ).sub(/function (\w+)/, "#{ name }.prototype.\\1 = function") }.join '; '
      "#{ parse( s(:defn, name, init[2], init[3]) ).sub(/return (?:null|(.*))\}\z/, '\1}') }#{ '; ' if block and not block.empty?}#{ block }"

    when :args
      sexp.join(', ')
      
    when :dstr
      sexp.unshift s(:str, sexp.shift)
      sexp.collect{ |s| parse s }.join(' + ')
      
    when :evstr
      parse sexp.shift
      
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
