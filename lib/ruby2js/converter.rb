require 'ruby2js/serializer'

module Ruby2JS
  class Error < NotImplementedError
    def initialize(message, ast)
      message += ' at ' + ast.loc.expression.source_buffer.name.to_s
      message += ':' + ast.loc.expression.line.inspect
      message += ':' + ast.loc.expression.column.to_s
      super(message)
    end
  end

  class Converter < Serializer
    attr_accessor :ast
    
    LOGICAL   = :and, :not, :or
    OPERATORS = [:[], :[]=], [:not, :!], [:**], [:*, :/, :%], [:+, :-], 
      [:>>, :<<], [:&], [:^, :|], [:<=, :<, :>, :>=], [:==, :!=, :===, :"!=="],
      [:and, :or]
    
    INVERT_OP = {
      :<  => :>=,
      :<= => :>,
      :== => :!=,
      :!= => :==,
      :>  => :<=,
      :>= => :<,
      :=== => :'!=='
    }

    GROUP_OPERATORS = [:begin, :dstr, :dsym, :and, :or, :casgn, :if]

    VASGN = [:cvasgn, :ivasgn, :gvasgn, :lvasgn]

    attr_accessor :binding, :ivars

    def initialize( ast, comments, vars = {} )
      super()

      @ast, @comments, @vars = ast, comments, vars.dup
      @varstack = []
      @scope = ast
      @inner = nil
      @rbstack = []
      @next_token = :return

      @handlers = {}
      @@handlers.each do |name|
        @handlers[name] = method("on_#{name}")
      end

      @state = nil
      @block_this = nil
      @block_depth = nil
      @prop = nil
      @instance_method = nil
      @prototype = nil
      @class_parent = nil
      @class_name = nil
      @jsx = false

      @eslevel = :es5
      @strict = false
    end

    def width=(width)
      @width = width
    end

    def convert
      scope @ast 

      if @strict
        if @sep == '; '
          @lines.first.unshift "\"use strict\"#@sep"
        else
          @lines.unshift Line.new('"use strict";')
        end
      end
    end

    def operator_index op
      OPERATORS.index( OPERATORS.find{ |el| el.include? op } ) || -1
    end
    
    # define a new scope; primarily determines what variables are visible and deals with hoisting of
    # declarations
    def scope( ast, args=nil )
      scope, @scope = @scope, ast
      inner, @inner = @inner, nil 
      mark = output_location
      @varstack.push @vars
      @vars = args if args
      @vars = Hash[@vars.map {|key, value| [key, true]}]

      parse( ast, :statement )

      # retroactively add a declaration for 'pending' variables
      vars = @vars.select {|key, value| value == :pending}.keys
      unless vars.empty?
        insert mark, "#{es2015 ? 'let' : 'var'} #{vars.join(', ')}#{@sep}"
        vars.each {|var| @vars[var] = true}
      end
    ensure
      @vars = @varstack.pop
      @scope = scope
      @inner = inner
    end

    # handle the oddity where javascript considers there to be a scope (e.g. the body of an if statement),
    # whereas Ruby does not.
    def jscope( ast, args=nil )
      @varstack.push @vars
      @vars = args if args
      @vars = Hash[@vars.map {|key, value| [key, true]}]

      parse( ast, :statement )
    ensure
      pending = @vars.select {|key, value| value == :pending}
      @vars = @varstack.pop
      @vars.merge! pending
    end

    def s(type, *args)
      Parser::AST::Node.new(type, args)
    end

    attr_accessor :strict, :eslevel

    def es2015
      @eslevel >= 2015
    end

    def es2016
      @eslevel >= 2016
    end

    def es2017
      @eslevel >= 2017
    end

    def es2018
      @eslevel >= 2018
    end

    def es2019
      @eslevel >= 2019
    end

    def es2020
      @eslevel >= 2020
    end

    @@handlers = []
    def self.handle(*types, &block)
      types.each do |type| 
        define_method("on_#{type}", block)
        @@handlers << type
      end
    end

    # extract comments that either precede or are included in the node.
    # remove from the list this node may appear later in the tree.
    def comments(ast)
      if ast.loc and ast.loc.respond_to? :expression
        expression = ast.loc.expression

        list = @comments[ast].select do |comment|
          expression.source_buffer == comment.loc.expression.source_buffer and
          comment.loc.expression.begin_pos < expression.end_pos
        end
      else
        list = @comments[ast]
      end

      @comments[ast] -= list

      list.map do |comment|
        if comment.text.start_with? '=begin'
          if comment.text.include? '*/'
            comment.text.sub(/\A=begin/, '').sub(/^=end\Z/, '').gsub(/^/, '//')
          else
            comment.text.sub(/\A=begin/, '/*').sub(/^=end\Z/, '*/')
          end
        else
          comment.text.sub(/^#/, '//') + "\n"
        end
      end
    end

    def parse(ast, state=:expression)
      oldstate, @state = @state, state
      oldast, @ast = @ast, ast
      return unless ast

      handler = @handlers[ast.type]

      unless handler
        raise Error.new("unknown AST type #{ ast.type }", ast)
      end

      if state == :statement and not @comments[ast].empty?
        comments(ast).each {|comment| puts comment.chomp}
      end

      handler.call(*ast.children)
    ensure
      @ast = oldast
      @state = oldstate
    end

    def parse_all(*args)
      @options = (Hash === args.last) ? args.pop : {}
      sep = @options[:join].to_s
      state = @options[:state] || :expression

      index = 0
      args.each do |arg|
        put sep unless index == 0
        parse arg, state
        index += 1 unless arg == s(:begin)
      end
    end
    
    def group( ast )
      if [:dstr, :dsym].include? ast.type and es2015
        parse ast
      else
        put '('; parse ast; put ')'
      end
    end

    def timestamp(file)
      super

      return unless file

      walk = proc do |ast|
        if ast.loc and ast.loc.expression
          filename = ast.loc.expression.source_buffer.name
          if filename and not filename.empty?
            filename = filename.dup.untaint
            @timestamps[filename] ||= File.mtime(filename)
          end
        end

        ast.children.each do |child|
          walk[child] if child.is_a? Parser::AST::Node
        end
      end

      walk[@ast] if @ast
    end
  end
end

module Parser
  module AST
    class Node
      def is_method?
        return false if type == :attr
        return true if type == :call
        return true unless loc

        if loc.respond_to? :selector
          return true if children.length > 2
          selector = loc.selector
        elsif type == :defs
          return true if children[1] =~ /[!?]$/
          return true if children[2].children.length > 0
          selector = loc.name
        elsif type == :def
          return true if children[0] =~ /[!?]$/
          return true if children[1].children.length > 0
          selector = loc.name
        end

        return true unless selector and selector.source_buffer
        selector.source_buffer.source[selector.end_pos] == '('
      end
    end
  end
end

# see https://github.com/whitequark/parser/blob/master/doc/AST_FORMAT.md

require 'ruby2js/converter/arg'
require 'ruby2js/converter/args'
require 'ruby2js/converter/array'
require 'ruby2js/converter/begin'
require 'ruby2js/converter/block'
require 'ruby2js/converter/blockpass'
require 'ruby2js/converter/boolean'
require 'ruby2js/converter/break'
require 'ruby2js/converter/case'
require 'ruby2js/converter/casgn'
require 'ruby2js/converter/class'
require 'ruby2js/converter/class2'
require 'ruby2js/converter/const'
require 'ruby2js/converter/cvar'
require 'ruby2js/converter/cvasgn'
require 'ruby2js/converter/def'
require 'ruby2js/converter/defs'
require 'ruby2js/converter/defined'
require 'ruby2js/converter/dstr'
require 'ruby2js/converter/fileline'
require 'ruby2js/converter/for'
require 'ruby2js/converter/hash'
require 'ruby2js/converter/if'
require 'ruby2js/converter/in'
require 'ruby2js/converter/ivar'
require 'ruby2js/converter/ivasgn'
require 'ruby2js/converter/kwbegin'
require 'ruby2js/converter/literal'
require 'ruby2js/converter/logical'
require 'ruby2js/converter/masgn'
require 'ruby2js/converter/module'
require 'ruby2js/converter/next'
require 'ruby2js/converter/nil'
require 'ruby2js/converter/nthref'
require 'ruby2js/converter/opasgn'
require 'ruby2js/converter/prototype'
require 'ruby2js/converter/regexp'
require 'ruby2js/converter/return'
require 'ruby2js/converter/self'
require 'ruby2js/converter/send'
require 'ruby2js/converter/super'
require 'ruby2js/converter/sym'
require 'ruby2js/converter/undef'
require 'ruby2js/converter/until'
require 'ruby2js/converter/untilpost'
require 'ruby2js/converter/var'
require 'ruby2js/converter/vasgn'
require 'ruby2js/converter/while'
require 'ruby2js/converter/whilepost'
require 'ruby2js/converter/xstr'
require 'ruby2js/converter/xnode'
