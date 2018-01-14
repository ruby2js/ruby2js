begin
  # silence warnings, see 
  # https://github.com/whitequark/parser/issues/346#issuecomment-317617695
  # https://github.com/bbatsov/rubocop/issues/1819#issuecomment-95280926
  old_verbose, $VERBOSE = $VERBOSE, nil
  require 'parser/current'
ensure
  $VERBOSE = old_verbose
end

require 'ruby2js/converter'

module Ruby2JS
  class SyntaxError < RuntimeError
  end

  @@eslevel_default = 2009 # ecmascript 5

  def self.eslevel_default
    @@eslevel_default
  end

  def self.eslevel_default=(level)
    @@eslevel_default = level
  end

  module Filter
    DEFAULTS = []

    module SEXP
      # construct an AST Node
      def s(type, *args)
        Parser::AST::Node.new type, args
      end

      def S(type, *args)
        @ast.updated(type, args)
      end
    end

    class Processor < Parser::AST::Processor
      BINARY_OPERATORS = Converter::OPERATORS[2..-1].flatten

      def initialize(comments)
        @comments = comments
        @ast = nil
      end

      def options=(options)
        @options = options
      end

      def es2015
        @options[:eslevel] >= 2015
      end

      def es2016
        @options[:eslevel] >= 2016
      end

      def es2017
        @options[:eslevel] >= 2017
      end

      def process(node)
        ast, @ast = @ast, node
        replacement = super

        if replacement != node and @comments[node]
          @comments[replacement] = @comments[node]
        end

        replacement
      ensure
        @ast = ast
      end

      # handle all of the 'invented' ast types
      def on_async(node); on_def(node); end
      def on_asyncs(node); on_defs(node); end
      def on_attr(node); on_send(node); end
      def on_autoreturn(node); on_return(node); end
      def on_await(node); on_send(node); end
      def on_call(node); on_send(node); end
      def on_constructor(node); on_def(node); end
      def on_defp(node); on_defs(node); end
      def on_for_of(node); on_for(node); end
      def on_in?(node); on_send(node); end
      def on_method(node); on_send(node); end
      def on_prop(node); on_array(node); end
      def on_prototype(node); on_begin(node); end
      def on_sendw(node); on_send(node); end
      def on_undefined?(node); on_defined?(node); end

      # provide a method so filters can call 'super'
      def on_sym(node); node; end

      # convert map(&:symbol) to a block
      def on_send(node)
        if node.children.length > 2 and node.children.last.type == :block_pass
          method = node.children.last.children.first.children.last
          if BINARY_OPERATORS.include? method
            return on_block s(:block, s(:send, *node.children[0..-2]),
              s(:args, s(:arg, :a), s(:arg, :b)), s(:return,
              process(s(:send, s(:lvar, :a), method, s(:lvar, :b)))))
          else
            return on_block s(:block, s(:send, *node.children[0..-2]),
              s(:args, s(:arg, :item)), s(:return,
              process(s(:attr, s(:lvar, :item), method))))
          end
        end
        super
      end
    end
  end

  def self.convert(source, options={})
    options[:eslevel] ||= @@eslevel_default

    if Proc === source
      file,line = source.source_location
      source = File.read(file.dup.untaint).untaint
      ast, comments = parse(source)
      comments = Parser::Source::Comment.associate(ast, comments) if ast
      ast = find_block( ast, line )
      options[:file] ||= file
    elsif Parser::AST::Node === source
      ast, comments = source, {}
      source = ast.loc.expression.source_buffer.source
    else
      ast, comments = parse( source, options[:file] )
      comments = Parser::Source::Comment.associate(ast, comments) if ast
    end

    filters = options[:filters] || Filter::DEFAULTS

    unless filters.empty?
      filter = Filter::Processor
      filters.reverse.each do |mod|
        filter = Class.new(filter) {include mod} 
      end
      filter = filter.new(comments)
      filter.options = options
      ast = filter.process(ast)
    end

    ruby2js = Ruby2JS::Converter.new(ast, comments)

    ruby2js.binding = options[:binding]
    ruby2js.ivars = options[:ivars]
    ruby2js.eslevel = options[:eslevel]
    if ruby2js.binding and not ruby2js.ivars
      ruby2js.ivars = ruby2js.binding.eval \
        'Hash[instance_variables.map {|var| [var, instance_variable_get(var)]}]'
    elsif options[:scope] and not ruby2js.ivars
      scope = options.delete(:scope)
      ruby2js.ivars = Hash[scope.instance_variables.map {|var|
        [var, scope.instance_variable_get(var)]}]
    end

    ruby2js.width = options[:width] if options[:width]

    ruby2js.enable_vertical_whitespace if source.include? "\n"

    ruby2js.convert

    ruby2js.timestamp options[:file]

    ruby2js
  end
  
  def self.parse(source, file=nil)
    Parser::CurrentRuby.parse_with_comments(source.encode('utf-8'), file)
  rescue Parser::SyntaxError => e
    split = source[0..e.diagnostic.location.begin_pos].split("\n")
    line, col = split.length, split.last.length
    message = "line #{line}, column #{col}: #{e.diagnostic.message}"
    message += "\n in file #{file}" if file
    raise Ruby2JS::SyntaxError.new(message)
  end

  def self.find_block(ast, line)
    if ast.type == :block and ast.loc.expression.line == line
      return ast.children.last
    end

    ast.children.each do |child|
      if Parser::AST::Node === child
        block = find_block child, line
        return block if block
      end
    end

    nil
  end
end
