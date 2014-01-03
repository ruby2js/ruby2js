require 'parser/current'

module Ruby2JS
  class Converter
    LOGICAL   = :and, :not, :or
    OPERATORS = [:[], :[]=], [:not, :!], [:*, :/, :%], [:+, :-], [:>>, :<<], 
      [:<=, :<, :>, :>=], [:==, :!=, :===, :"!=="], [:and, :or]
    
    attr_accessor :binding, :ivars

    def initialize( ast, vars = {} )
      @ast, @vars = ast, vars.dup
      @sep = '; '
      @nl = ''
      @ws = ' '
      @varstack = []
      @width = 80
      @next_token = :return

      @handlers = {}
      @@handlers.each do |name|
        @handlers[name] = method("on_#{name}")
      end
    end
    
    def enable_vertical_whitespace
      @sep = ";\n"
      @nl = "\n"
      @ws = @nl
    end

    def binding=(binding)
      @binding = binding
    end

    def width=(width)
      @width = width
    end

    def to_js
      parse( @ast, :statement )
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

    def is_method?(node)
      return false unless node.type == :send
      return true unless node.loc
      selector = node.loc.selector
      return true unless selector.source_buffer
      selector.source_buffer.source[selector.end_pos] == '('
    end

    @@handlers = []
    def self.handle(*types, &block)
      types.each do |type| 
        define_method("on_#{type}", block)
        @@handlers << type
      end
    end

    def parse(ast, state=:expression)
      return ast unless ast

      @state = state
      @ast = ast
      handler = @handlers[ast.type]

      unless handler
        raise NotImplementedError, "unknown AST type #{ ast.type }"
      end

      handler.call(*ast.children) if handler
    end
    
    def group( ast )
      "(#{ parse ast })"
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
require 'ruby2js/converter/ivar'
require 'ruby2js/converter/ivasgn'
require 'ruby2js/converter/kwbegin'
require 'ruby2js/converter/literal'
require 'ruby2js/converter/logical'
require 'ruby2js/converter/masgn'
require 'ruby2js/converter/module'
require 'ruby2js/converter/next'
require 'ruby2js/converter/nil'
require 'ruby2js/converter/opasgn'
require 'ruby2js/converter/prototype'
require 'ruby2js/converter/regexp'
require 'ruby2js/converter/return'
require 'ruby2js/converter/self'
require 'ruby2js/converter/send'
require 'ruby2js/converter/sym'
require 'ruby2js/converter/undef'
require 'ruby2js/converter/until'
require 'ruby2js/converter/untilpost'
require 'ruby2js/converter/var'
require 'ruby2js/converter/vasgn'
require 'ruby2js/converter/while'
require 'ruby2js/converter/whilepost'
require 'ruby2js/converter/xstr'
