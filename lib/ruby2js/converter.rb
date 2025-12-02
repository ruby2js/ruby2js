require 'ruby2js/serializer'

module Ruby2JS
  class Error < NotImplementedError
    def initialize(message, ast)
      loc = ast.loc
      if loc
        if loc.respond_to?(:expression) && loc.expression
          # Parser gem location
          message += ' at ' + loc.expression.source_buffer.name.to_s
          message += ':' + loc.expression.line.inspect
          message += ':' + loc.expression.column.to_s
        elsif loc.is_a?(Hash) && loc[:start_offset]
          # Ruby2JS::Node location (prism-direct)
          message += ' at offset ' + loc[:start_offset].to_s
        end
      end
      super(message)
    end
  end

  class Converter < Serializer
    attr_accessor :ast

    LOGICAL   = :and, :not, :or
    OPERATORS = [:[], :[]=], [:not, :!], [:**], [:*, :/, :%], [:+, :-], 
      [:>>, :<<], [:&], [:^, :|], [:<=, :<, :>, :>=],
      [:==, :!=, :===, :"!==", :=~, :!~], [:and, :or]
    
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

    attr_accessor :binding, :ivars, :namespace

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
      @autobind = true

      @eslevel = :es5
      @strict = false
      @comparison = :equality
      @or = :logical
      @truthy = :js
      @need_truthy_helpers = Set.new
      @underscored_private = true
      @redoable = false
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

      # Inject truthy helpers if needed
      unless @need_truthy_helpers.empty?
        helpers = []
        helpers << 'const $T=v=>v!==false&&v!=null' if @need_truthy_helpers.include?(:T)
        helpers << 'const $ror=(a,b)=>$T(a)?a:b()' if @need_truthy_helpers.include?(:ror)
        helpers << 'const $rand=(a,b)=>$T(a)?b():a' if @need_truthy_helpers.include?(:rand)

        helper_line = helpers.join('; ')
        if @sep == '; '
          @lines.first.unshift "#{helper_line}#@sep"
        else
          @lines.unshift Line.new(helper_line + ';')
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
      if defined?(Parser::AST::Node)
        Parser::AST::Node.new(type, args)
      else
        Ruby2JS::Node.new(type, args)
      end
    end

    attr_accessor :strict, :eslevel, :module_type, :comparison, :or, :truthy, :underscored_private

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

    def es2021
      @eslevel >= 2021
    end

    def es2022
      @eslevel >= 2022
    end

    def es2023
      @eslevel >= 2023
    end

    def es2024
      @eslevel >= 2024
    end

    def es2025
      @eslevel >= 2025
    end

    @@handlers = []
    def self.handle(*types, &block)
      types.each do |type| 
        define_method("on_#{type}", block)
        @@handlers << type
      end
    end

    # extract comments that either precede or are included in the node.
    # remove from the list so this node's comments won't appear again later in the tree.
    def comments(ast)
      comment_list, comment_key = find_comment_entry(ast)

      if ast.loc and ast.loc.respond_to? :expression
        expression = ast.loc.expression

        list = comment_list.select do |comment|
          expression.source_buffer == comment.loc.expression.source_buffer and
          comment.loc.expression.begin_pos < expression.end_pos
        end
      else
        list = comment_list
      end

      if @comments.key?(comment_key) && @comments[comment_key]
        @comments[comment_key] -= list
      end

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

    private

    # Find comments for an AST node using multiple lookup strategies:
    # 1. Direct lookup by object identity
    # 2. Location-based lookup (for nodes recreated by filters with same location)
    # 3. First-child location lookup (for synthetic nodes wrapping real content)
    # Returns [comment_list, comment_key] where comment_key is used for removal
    def find_comment_entry(ast)
      # First try direct lookup by object identity
      comment_list = @comments[ast]
      return [comment_list, ast] if comment_list && !comment_list.empty?

      # If ast has location info, try location-based lookup
      # This handles cases where filters created new nodes with same location
      if ast.loc && ast.loc.respond_to?(:expression) && ast.loc.expression
        expression = ast.loc.expression
        @comments.each do |key, value|
          next if key == :_raw || value.nil? || value.empty?
          next unless key.respond_to?(:loc) && key.loc&.respond_to?(:expression)
          key_expr = key.loc.expression
          next unless key_expr
          if key_expr.source_buffer == expression.source_buffer &&
             key_expr.begin_pos == expression.begin_pos &&
             key_expr.end_pos == expression.end_pos
            return [value, key]
          end
        end
      end

      # For synthetic nodes (no location), try to find comments via first child with location
      if !ast.loc || !ast.loc.respond_to?(:expression) || !ast.loc.expression
        first_loc = find_first_location(ast)
        if first_loc
          @comments.each do |key, value|
            next if key == :_raw || value.nil? || value.empty?
            next unless key.respond_to?(:loc) && key.loc&.respond_to?(:expression)
            key_expr = key.loc.expression
            next unless key_expr && key_expr.source_buffer == first_loc.source_buffer
            # If the key starts at or near where our content starts, use its comments
            if key_expr.begin_pos <= first_loc.begin_pos + 1
              return [value, key]
            end
          end
        end
        # If no first_loc (empty synthetic node), don't try to find comments
      end

      [[], ast]
    end

    # Find the first source location in an AST tree (depth-first)
    def find_first_location(ast)
      return nil unless ast.respond_to?(:children)
      if ast.loc && ast.loc.respond_to?(:expression) && ast.loc.expression
        return ast.loc.expression
      end
      ast.children.each do |child|
        next unless child.respond_to?(:type) && child.respond_to?(:children)
        loc = find_first_location(child)
        return loc if loc
      end
      nil
    end

    public

    def parse(ast, state=:expression)
      oldstate, @state = @state, state
      oldast, @ast = @ast, ast
      return unless ast

      handler = @handlers[ast.type]

      unless handler
        raise Error.new("unknown AST type #{ ast.type }", ast)
      end

      if state == :statement
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

    def redoable(block)
      save_redoable = @redoable

      has_redo = proc do |node|
        node.children.any? do |child|
          next false unless child.respond_to?(:type) && child.respond_to?(:children)
          next true if child.type == :redo
          next false if %i[for while while_post until until_post].include? child.type
          has_redo[child]
        end
      end

      @redoable = has_redo[@ast]

      if @redoable
        put es2015 ? 'let ' : 'var '
        put "redo$#@sep"
        puts 'do {'
        put "redo$ = false#@sep"
        scope block
        put "#@nl} while(redo$)"
      else
        scope block
      end
    ensure
      @redoable = save_redoable
    end

    def timestamp(file)
      super

      return unless file

      walk = proc do |ast|
        if ast.loc and ast.loc.respond_to?(:expression) and ast.loc.expression
          filename = ast.loc.expression.source_buffer.name
          if filename and not filename.empty?
            @timestamps[filename] ||= File.mtime(filename) rescue nil
          end
        end

        ast.children.each do |child|
          walk[child] if child.respond_to?(:type) && child.respond_to?(:children)
        end
      end

      walk[@ast] if @ast
    end
  end
end

# Add is_method? to Parser::AST::Node for distinguishing method calls from property access
# Only do this if the Parser gem has been loaded
if defined?(Parser::AST::Node) && Parser::AST::Node.ancestors.include?(AST::Node)
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
end

# see https://github.com/whitequark/parser/blob/master/doc/AST_FORMAT.md

require 'ruby2js/converter/arg'
require 'ruby2js/converter/args'
require 'ruby2js/converter/array'
require 'ruby2js/converter/assign'
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
require 'ruby2js/converter/ensure'
require 'ruby2js/converter/fileline'
require 'ruby2js/converter/for'
require 'ruby2js/converter/hash'
require 'ruby2js/converter/hide'
require 'ruby2js/converter/if'
require 'ruby2js/converter/in'
require 'ruby2js/converter/import'
require 'ruby2js/converter/ivar'
require 'ruby2js/converter/ivasgn'
require 'ruby2js/converter/kwbegin'
require 'ruby2js/converter/literal'
require 'ruby2js/converter/logical'
require 'ruby2js/converter/masgn'
require 'ruby2js/converter/match'
require 'ruby2js/converter/module'
require 'ruby2js/converter/next'
require 'ruby2js/converter/nil'
require 'ruby2js/converter/nthref'
require 'ruby2js/converter/opasgn'
require 'ruby2js/converter/prototype'
require 'ruby2js/converter/redo'
require 'ruby2js/converter/regexp'
require 'ruby2js/converter/retry'
require 'ruby2js/converter/return'
require 'ruby2js/converter/self'
require 'ruby2js/converter/send'
require 'ruby2js/converter/super'
require 'ruby2js/converter/sym'
require 'ruby2js/converter/taglit'
require 'ruby2js/converter/undef'
require 'ruby2js/converter/until'
require 'ruby2js/converter/untilpost'
require 'ruby2js/converter/var'
require 'ruby2js/converter/vasgn'
require 'ruby2js/converter/while'
require 'ruby2js/converter/whilepost'
require 'ruby2js/converter/xstr'
require 'ruby2js/converter/xnode'
require 'ruby2js/converter/yield'
