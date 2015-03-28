require 'parser/current'

require 'ruby2js/serializer'

module Ruby2JS
  class Converter < Serializer
    LOGICAL   = :and, :not, :or
    OPERATORS = [:[], :[]=], [:not, :!], [:*, :/, :%], [:+, :-], [:>>, :<<], 
      [:&], [:^, :|], [:<=, :<, :>, :>=], [:==, :!=, :===, :"!=="], [:and, :or]
    
    INVERT_OP = {
      :<  => :>=,
      :<= => :>,
      :== => :!=,
      :!= => :==,
      :>  => :<=,
      :>= => :<,
      :=== => :'!=='
    }

    GROUP_OPERATORS = [:begin, :dstr, :dsym, :and, :or]

    attr_accessor :binding, :ivars

    def initialize( ast, comments, vars = {} )
      super()

      @ast, @comments, @vars = ast, comments, vars.dup
      @varstack = []
      @rbstack = []
      @next_token = :return

      @handlers = {}
      @@handlers.each do |name|
        @handlers[name] = method("on_#{name}")
      end
    end
    
    def binding=(binding)
      @binding = binding
    end

    def width=(width)
      @width = width
    end

    def to_js
      parse( @ast, :statement )
      serialize
    end

    def operator_index op
      OPERATORS.index( OPERATORS.find{ |el| el.include? op } ) || -1
    end
    
    def scope( ast, args=nil )
      @varstack.push @vars.dup
      @vars = args if args
      parse( ast, :statement )
    ensure
      @vars = @varstack.pop
    end

    def s(type, *args)
      Parser::AST::Node.new(type, args)
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
        comment.text.sub(/^#/, '//') + "\n"
      end
    end

    def parse(ast, state=:expression)
      oldstate, @state = @state, state
      oldast, @ast = @ast, ast
      return unless ast

      handler = @handlers[ast.type]

      unless handler
        raise NotImplementedError, "unknown AST type #{ ast.type }"
      end

      if state == :statement and not @comments[ast].empty?
        comments(ast).each {|comment| puts comment.chomp}
      end

      handler.call(*ast.children)
    ensure
      @ast = oldast
    end

    def parse_all(*args)
      options = (Hash === args.last) ? args.pop : {}
      sep = options[:join].to_s
      state = options[:state] || :expression

      args.each_with_index do |arg, index|
        put sep unless index == 0
        parse arg, state
      end
    end
    
    def group( ast )
      put '('; parse ast; put ')'
    end
  end
end

module Parser
  module AST
    class Node
      def is_method?
        return false if type == :attr
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

        return true unless selector.source_buffer
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
require 'ruby2js/converter/const'
require 'ruby2js/converter/cvar'
require 'ruby2js/converter/cvasgn'
require 'ruby2js/converter/def'
require 'ruby2js/converter/defs'
require 'ruby2js/converter/defined'
require 'ruby2js/converter/dstr'
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
