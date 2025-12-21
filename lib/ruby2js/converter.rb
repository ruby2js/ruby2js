require_relative 'serializer'

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

    GROUP_OPERATORS = [:begin, :dstr, :dsym, :and, :or, :nullish, :casgn, :if, :await]

    VASGN = [:cvasgn, :ivasgn, :gvasgn, :lvasgn]

    # JavaScript reserved words that are valid Ruby identifiers
    # These get prefixed with $ when used as local variables
    # NOTE: Words like 'if', 'class', 'while' are reserved in BOTH languages,
    # so they can never appear as Ruby variable names and don't need handling.
    # Also excludes pass-through identifiers used by Ruby2JS:
    #   true/false/null/this - used by jQuery filter, etc.
    # The functions filter maps `debugger` as a statement to JS's `debugger;`
    # Using array instead of Set for selfhost compatibility (JS Set uses .has() not .includes())
    JS_RESERVED = %w[
      catch const continue debugger default delete enum export extends finally
      function import instanceof new switch throw try typeof var void with
      let static implements interface package private protected public
    ].freeze

    attr_accessor :binding, :ivars, :namespace

    # Class variable to store last comments for debugging
    # Note: In Ruby this is @@, in JS selfhost this becomes a static property
    @@last_comments = nil

    def self.last_comments
      @@last_comments
    end

    def self.last_comments=(value)
      @@last_comments = value
    end

    # Expose comments hash for debugging (named differently from comments method)
    def comments_hash
      @comments
    end

    def initialize( ast, comments, vars = {} )
      super()

      @ast, @comments, @vars = ast, comments, vars.dup # Pragma: hash

      # Store comments for debugging (class variable for access after conversion)
      @@last_comments = @comments

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

      @eslevel = 2020
      @strict = false
      @comparison = :equality
      @or = :auto
      @truthy = :js
      @boolean_context = false
      @need_truthy_helpers = []
      @underscored_private = true
      @nullish_to_s = false
      @redoable = false
    end

    def width=(width)
      @width = width
    end

    def convert
      scope @ast

      # Output orphan comments (comments after all code)
      orphan_list = @comments.respond_to?(:get) ? @comments.get(:_orphan) : @comments[:_orphan]
      if orphan_list
        orphan_list.each do |comment|
          text = comment.respond_to?(:text) ? comment.text : comment.to_s
          next if text =~ /#\s*Pragma:/i
          # Add newline before orphan comment, then output comment
          sput text.sub(/^#/, '//')
        end
      end

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

        helpers << 'let $T = (v) => v !== false && v != null' if @need_truthy_helpers.include?(:T)
        helpers << 'let $ror = (a, b) => $T(a) ? a : b()' if @need_truthy_helpers.include?(:ror)
        helpers << 'let $rand = (a, b) => $T(a) ? b() : a' if @need_truthy_helpers.include?(:rand)

        if @sep == '; '
          @lines.first.unshift helpers.join(@sep) + @sep
        else
          helpers.reverse.each do |helper|
            @lines.unshift Line.new(helper + ';')
          end
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
      @vars = Hash[@vars.map {|key, value| [key, true]}] # Pragma: entries

      parse( ast, :statement )

      # retroactively add a declaration for 'pending' variables
      vars = @vars.select {|key, value| value == :pending}.keys() # Pragma: entries
      unless vars.empty?
        insert mark, "let #{vars.map { |v| jsvar(v) }.join(', ')}#{@sep}"
        vars.each {|var| @vars[var] = true}
      end
    ensure
      @vars = @varstack.pop()
      @scope = scope
      @inner = inner
    end

    # handle the oddity where javascript considers there to be a scope (e.g. the body of an if statement),
    # whereas Ruby does not.
    def jscope( ast, args=nil )
      @varstack.push @vars
      @vars = args if args
      @vars = Hash[@vars.map {|key, value| [key, true]}] # Pragma: entries

      parse( ast, :statement )
    ensure
      pending = @vars.select {|key, value| value == :pending} # Pragma: entries
      @vars = @varstack.pop()
      @vars.merge! pending
    end

    def s(type, *args)
      unless defined?(RUBY2JS_SELFHOST)
        if defined?(Parser::AST::Node)
          return Parser::AST::Node.new(type, args)
        end
      end
      Ruby2JS::Node.new(type, args)
    end

    # Escape JavaScript reserved words by prefixing with $
    # var → $var, class → $class, etc.
    def jsvar(name)
      name = name.to_s
      JS_RESERVED.include?(name) ? "$#{name}" : name
    end

    attr_accessor :strict, :eslevel, :module_type, :comparison, :or, :truthy, :underscored_private, :nullish_to_s

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

      if ast.loc and ast.loc.respond_to?(:expression) and ast.loc.expression
        expression = ast.loc.expression

        list = comment_list.select do |comment|
          next false unless comment.loc and comment.loc.respond_to?(:expression) and comment.loc.expression
          expression.source_buffer == comment.loc.expression.source_buffer and
          comment.loc.expression.begin_pos < expression.end_pos
        end
      else
        list = comment_list
      end

      # Remove retrieved comments so they don't appear again
      # Ruby version uses Hash with -= array subtraction
      unless defined?(RUBY2JS_SELFHOST) # Pragma: skip
        if @comments.key?(comment_key) && @comments[comment_key]
          @comments[comment_key] -= list
        end
      end

      # JS selfhost: Map-based removal
      # Note: We set to empty array instead of deleting because the functions filter
      # transforms .delete(key) to `delete obj[key]` which doesn't work for Maps.
      # The find_comment_entry forEach loop skips entries with value.length == 0.
      if defined?(RUBY2JS_SELFHOST) # Pragma: delete
        if @comments && @comments.respond_to?(:has) && @comments.has(comment_key)
          remaining = @comments.get(comment_key).filter { |c| !list.include?(c) }
          @comments.set(comment_key, remaining)
        end
      end # Pragma: keep

      list.map do |comment|
        # Skip pragma comments - they're directives, not documentation
        text = comment.text
        next nil if text =~ /#\s*Pragma:/i

        if text.start_with? '=begin'
          # Convert =begin...=end to JS comments
          # Note: \A/\Z are Ruby-only anchors, not valid in JS.
          # Use ^/$ which work in both Ruby (default) and JS (with multiline flag).
          if text.include? '*/'
            # Contains */, so can't use /* */ - convert each line to //
            result = text.sub(/^=begin/, '').sub(/^=end$/, '').gsub(/^/, '//')
            # JS gsub(^) matches at end of string after final \n, Ruby doesn't.
            # Strip trailing // only if string ends with it (no newline after).
            result = result[0..-3] if result.end_with?('//')
            result
          else
            # Safe to use /* */, just replace markers
            text.sub(/^=begin/, '/*').sub(/^=end$/, '*/')
          end
        else
          # Handle comments - ensure they have // prefix
          if text.start_with?('#')
            text.sub(/^#/, '//') + "\n"
          else
            '// ' + text + "\n"
          end
        end
      end.compact
    end

    private

    # Find comments for an AST node by direct identity lookup.
    # The pipeline's reassociate_comments handles position-based association,
    # so we only need simple direct lookup here.
    # Returns [comment_list, comment_key] where comment_key is used for removal
    def find_comment_entry(ast)
      # Direct lookup by object identity
      # Ruby uses Hash ([]), JS selfhost uses Map (.get())
      comment_list = @comments.respond_to?(:get) ? @comments.get(ast) : @comments[ast]
      return [comment_list, ast] if comment_list.is_a?(Array)
      [[], ast]
    end

    # Check if obj is an AST node (has type and children)
    # Safe for both Ruby and JS (doesn't throw on primitives)
    def ast_node?(obj)
      return false unless obj
      # In Ruby: respond_to? is safe for all objects
      # In JS: selfhost/converter filter transforms to add typeof guard
      obj.respond_to?(:type) && obj.respond_to?(:children)
    end

    # Output trailing comment for a node (on same line)
    def trailing_comment(ast)
      trailing_list = @comments.respond_to?(:get) ? @comments.get(:_trailing) : @comments[:_trailing]
      return unless trailing_list

      # Find trailing comment for this node
      # Match by type + location (type prevents :begin from matching its first child)
      ast_type = ast.type
      ast_begin = node_begin_pos(ast)
      # Note: Use explicit nil check because begin_pos can be 0 (falsy in JS)
      return if ast_begin.nil?

      trailing_list.each do |entry|
        node, comment = entry
        node_begin = node_begin_pos(node)
        next unless node.type == ast_type && node_begin == ast_begin
        text = comment.respond_to?(:text) ? comment.text : comment.to_s
        # Skip pragma comments
        return if text =~ /#\s*Pragma:/i
        # Append to current line (space + // + comment text without #)
        put ' ' + text.sub(/^#/, '//')
      end
    end

    # Get begin_pos from a node's location (safe for both Ruby and JS)
    def node_begin_pos(node)
      return nil unless node.respond_to?(:loc) && node.loc
      loc = node.loc
      if loc.respond_to?(:expression) && loc.expression
        loc.expression.begin_pos
      elsif loc.respond_to?(:[]) && loc[:expression]
        loc[:expression].begin_pos
      else
        nil
      end
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

      # Output trailing comments on same line (after statement)
      if state == :statement
        trailing_comment(ast)
      end
    ensure
      @ast = oldast
      @state = oldstate
    end

    def parse_all(*args)
      last_arg = args[-1]
      # In selfhost JS, is_a?(Hash) becomes Object check which matches Node too.
      # Add !respond_to?(:type) to exclude Node objects (they have a type property)
      @options = last_arg.is_a?(Hash) && !last_arg.respond_to?(:type) ? args.pop() : {}
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
      if [:dstr, :dsym].include? ast.type
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
          has_redo.call(child)
        end
      end

      @redoable = has_redo.call(@ast)

      if @redoable
        put 'let '
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
          walk.call(child) if child.respond_to?(:type) && child.respond_to?(:children)
        end
      end

      walk.call(@ast) if @ast
    end
  end
end

# Add is_method? to Parser::AST::Node for distinguishing method calls from property access
# Only do this if the Parser gem has been loaded
# NOTE: This entire block is parser-gem specific and skipped during selfhost transpilation
unless defined?(RUBY2JS_SELFHOST) # Pragma: skip
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
end

# see https://github.com/whitequark/parser/blob/master/doc/AST_FORMAT.md

require_relative 'converter/arg'
require_relative 'converter/args'
require_relative 'converter/array'
require_relative 'converter/assign'
require_relative 'converter/begin'
require_relative 'converter/block'
require_relative 'converter/blockpass'
require_relative 'converter/boolean'
require_relative 'converter/break'
require_relative 'converter/case'
require_relative 'converter/casgn'
require_relative 'converter/class'
require_relative 'converter/class2'
require_relative 'converter/const'
require_relative 'converter/cvar'
require_relative 'converter/cvasgn'
require_relative 'converter/def'
require_relative 'converter/defs'
require_relative 'converter/defined'
require_relative 'converter/dstr'
require_relative 'converter/ensure'
require_relative 'converter/fileline'
require_relative 'converter/for'
require_relative 'converter/hash'
require_relative 'converter/hide'
require_relative 'converter/if'
require_relative 'converter/in'
require_relative 'converter/instanceof'
require_relative 'converter/import'
require_relative 'converter/ivar'
require_relative 'converter/ivasgn'
require_relative 'converter/kwbegin'
require_relative 'converter/literal'
require_relative 'converter/logical'
require_relative 'converter/masgn'
require_relative 'converter/match'
require_relative 'converter/module'
require_relative 'converter/next'
require_relative 'converter/nil'
require_relative 'converter/nthref'
require_relative 'converter/nullish'
require_relative 'converter/logical_or'
require_relative 'converter/opasgn'
require_relative 'converter/prototype'
require_relative 'converter/redo'
require_relative 'converter/regexp'
require_relative 'converter/retry'
require_relative 'converter/return'
require_relative 'converter/self'
require_relative 'converter/send'
require_relative 'converter/super'
require_relative 'converter/sym'
require_relative 'converter/taglit'
require_relative 'converter/undef'
require_relative 'converter/until'
require_relative 'converter/untilpost'
require_relative 'converter/var'
require_relative 'converter/vasgn'
require_relative 'converter/while'
require_relative 'converter/whilepost'
require_relative 'converter/xstr'
require_relative 'converter/xnode'
require_relative 'converter/yield'
