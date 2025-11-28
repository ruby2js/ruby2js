begin
  # silence warnings, see 
  # https://github.com/whitequark/parser/issues/346#issuecomment-317617695
  # https://github.com/bbatsov/rubocop/issues/1819#issuecomment-95280926
  old_verbose, $VERBOSE = $VERBOSE, nil
  require 'parser/current'
ensure
  $VERBOSE = old_verbose
end

require 'ruby2js/configuration_dsl' unless RUBY_ENGINE == 'opal'
require 'ruby2js/converter'
require 'ruby2js/filter'
require 'ruby2js/namespace'

module Ruby2JS
  class SyntaxError < RuntimeError
    attr_reader :diagnostic
    def initialize(message, diagnostic=nil)
      super(message)
      @diagnostic = diagnostic
    end
  end

  @@eslevel_default = 2009 # ecmascript 5
  @@eslevel_preset_default = 2021
  @@strict_default = false
  @@module_default = nil

  def self.eslevel_default
    @@eslevel_default
  end

  def self.eslevel_default=(level)
    @@eslevel_default = level
  end

  def self.strict_default
    @@strict_default
  end

  def self.strict_default=(level)
    @@strict_default = level
  end

  def self.module_default
    @@module_default
  end

  def self.module_default=(module_type)
    @@module_default = module_type
  end

  module Filter
    DEFAULTS = []

    module SEXP
      # construct an AST Node
      def s(type, *args)
        Parser::AST::Node.new type, args
      end

      # update existing node
      def S(type, *args)
        @ast.updated(type, args)
      end
    end

    class Processor < Parser::AST::Processor
      include Ruby2JS::Filter
      BINARY_OPERATORS = Converter::OPERATORS[2..-1].flatten

      attr_accessor :prepend_list, :disable_autoimports, :disable_autoexports, :namespace

      def initialize(comments)
        @comments = comments

        @ast = nil
        @exclude_methods = []
        @prepend_list = Set.new
      end

      def options=(options)
        @options = options

        @included = Filter.included_methods
        @excluded = Filter.excluded_methods

        include_all if options[:include_all]
        include_only(options[:include_only]) if options[:include_only]
        include(options[:include]) if options[:include]
        exclude(options[:exclude]) if options[:exclude]

        filters = options[:filters] || DEFAULTS
        @modules_enabled =
          (defined? Ruby2JS::Filter::ESM and
          filters.include? Ruby2JS::Filter::ESM) or
          (defined? Ruby2JS::Filter::CJS and
          filters.include? Ruby2JS::Filter::CJS)
      end

      def modules_enabled?
        @modules_enabled
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

      def es2018
        @options[:eslevel] >= 2018
      end

      def es2019
        @options[:eslevel] >= 2019
      end

      def es2020
        @options[:eslevel] >= 2020
      end

      def es2021
        @options[:eslevel] >= 2021
      end

      def es2022
        @options[:eslevel] >= 2022
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

      # handle all of the 'invented/synthetic' ast types
      def on_assign(node); end
      def on_async(node); on_def(node); end
      def on_asyncs(node); on_defs(node); end
      def on_attr(node); on_send(node); end
      def on_autoreturn(node); on_return(node); end
      def on_await(node); on_send(node); end
      def on_call(node); on_send(node); end
      def on_class_extend(node); on_send(node); end
      def on_class_hash(node); on_class(node); end
      def on_class_module(node); on_send(node); end
      def on_constructor(node); on_def(node); end
      def on_deff(node); on_def(node); end
      def on_defm(node); on_defs(node); end
      def on_defp(node); on_defs(node); end
      def on_for_of(node); on_for(node); end
      def on_in?(node); on_send(node); end
      def on_method(node); on_send(node); end
      def on_module_hash(node); on_module(node); end
      def on_prop(node); on_array(node); end
      def on_prototype(node); on_begin(node); end
      def on_send!(node); on_send(node); end
      def on_sendw(node); on_send(node); end
      def on_undefined?(node); on_defined?(node); end
      def on_defineProps(node); end
      def on_hide(node); on_begin(node); end
      def on_nil(node); end
      def on_xnode(node); end
      def on_export(node); end
      def on_import(node); end
      def on_taglit(node); on_pair(node); end

      # provide a method so filters can call 'super'
      def on_sym(node); node; end

      # convert numbered parameters block to a normal block
      def on_numblock(node)
        call, count, block = node.children

        process s(:block,
          call,
          s(:args, *((1..count).map {|i| s(:arg, "_#{i}")})),
          block
        )
      end

      # convert map(&:symbol) to a block
      def on_send(node)
        if node.children.length > 2 and node.children.last.type == :block_pass
          method = node.children.last.children.first.children.last
          # preserve csend type for optional chaining
          call_type = node.type == :csend ? :csend : :send
          if BINARY_OPERATORS.include? method
            return on_block s(:block, s(call_type, *node.children[0..-2]),
              s(:args, s(:arg, :a), s(:arg, :b)), s(:return,
              process(s(:send, s(:lvar, :a), method, s(:lvar, :b)))))
          elsif node.children.last.children.first.type == :sym
            return on_block s(:block, s(call_type, *node.children[0..-2]),
              s(:args, s(:arg, :item)), s(:return,
              process(s(:attr, s(:lvar, :item), method))))
          else
            super
          end
        end
        super
      end

      def on_csend(node)
        on_send(node)
      end
    end
  end

  # TODO: this method has gotten long and unwieldy!
  def self.convert(source, options={})
    Filter.autoregister unless RUBY_ENGINE == 'opal'
    options = options.dup

    if Proc === source
      file,line = source.source_location
      source = IO.read(file)
      ast, comments = parse(source)
      comments = Parser::Source::Comment.associate(ast, comments) if ast
      ast = find_block( ast, line )
      options[:file] ||= file
    elsif Parser::AST::Node === source
      ast, comments = source, {}
      source = ast.loc.expression.source_buffer.source
    else
      ast, comments = parse( source, options[:file] )
      comments = ast ? Parser::Source::Comment.associate(ast, comments) : {}
    end

    # check if magic comment is present
    first_comment = comments.values.first&.map(&:text)&.first
    if first_comment
      if first_comment.include?(" ruby2js: preset")
        options[:preset] = true
        if first_comment.include?("filters: ")
          options[:filters] = first_comment.match(%r(filters:\s*?([^\s]+)\s?.*$))[1].split(",").map(&:to_sym)
        end
        if first_comment.include?("eslevel: ")
          options[:eslevel] = first_comment.match(%r(eslevel:\s*?([^\s]+)\s?.*$))[1].to_i
        end
        if first_comment.include?("disable_filters: ")
          options[:disable_filters] = first_comment.match(%r(disable_filters:\s*?([^\s]+)\s?.*$))[1].split(",").map(&:to_sym)
        end
      end
      disable_autoimports = first_comment.include?(" autoimports: false")
      disable_autoexports = first_comment.include?(" autoexports: false")
    end

    unless RUBY_ENGINE == 'opal'
      unless options.key?(:config_file) || !File.exist?("config/ruby2js.rb")
        options[:config_file] ||= "config/ruby2js.rb"
      end

      if options[:config_file]
        options = ConfigurationDSL.load_from_file(options[:config_file], options).to_h
      end
    end

    if options[:preset]
      options[:eslevel] ||= @@eslevel_preset_default
      options[:filters] = Filter::PRESET_FILTERS + Array(options[:filters]).uniq
      if options[:disable_filters]
        options[:filters] -= options[:disable_filters]
      end
      options[:comparison] ||= :identity
      options[:underscored_private] = true unless options[:underscored_private] == false
    end
    options[:eslevel] ||= @@eslevel_default
    options[:strict] = @@strict_default if options[:strict] == nil
    options[:module] ||= @@module_default || :esm

    namespace = Namespace.new

    filters = Filter.require_filters(options[:filters] || Filter::DEFAULTS)

    unless filters.empty?
      filter_options = options.merge({ filters: filters })
      filters.dup.each do |filter|
        filters = filter.reorder(filters) if filter.respond_to? :reorder
      end

      filter = Filter::Processor
      filters.reverse.each do |mod|
        filter = Class.new(filter) {include mod} 
      end
      filter = filter.new(comments)

      filter.disable_autoimports = disable_autoimports
      filter.disable_autoexports = disable_autoexports
      filter.options = filter_options
      filter.namespace = namespace
      ast = filter.process(ast)

      unless filter.prepend_list.empty?
        prepend = filter.prepend_list.sort_by {|ast| ast.type == :import ? 0 : 1}
        prepend.reject! {|ast| ast.type == :import} if filter.disable_autoimports
        ast = Parser::AST::Node.new(:begin, [*prepend, ast])
      end
    end

    ruby2js = Ruby2JS::Converter.new(ast, comments)

    ruby2js.binding = options[:binding]
    ruby2js.ivars = options[:ivars]
    ruby2js.eslevel = options[:eslevel]
    ruby2js.strict = options[:strict]
    ruby2js.comparison = options[:comparison] || :equality
    ruby2js.or = options[:or] || :logical
    ruby2js.module_type = options[:module] || :esm
    ruby2js.underscored_private = (options[:eslevel] < 2022) || options[:underscored_private]

    ruby2js.namespace = namespace

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

    ruby2js.file_name = options[:file] || ast&.loc&.expression&.source_buffer&.name || ''

    ruby2js
  end
  
  def self.parse(source, file=nil, line=1)
    buffer = Parser::Source::Buffer.new(file, line)
    buffer.source = source.encode('UTF-8')
    parser = Parser::CurrentRuby.new
    parser.diagnostics.all_errors_are_fatal = true
    parser.diagnostics.consumer = lambda {|diagnostic| nil}
    parser.builder.emit_file_line_as_literals = false
    parser.parse_with_comments(buffer)
  rescue Parser::SyntaxError => e
    split = source[0..e.diagnostic.location.begin_pos].split("\n")
    line, col = split.length, split.last.length
    message = "line #{line}, column #{col}: #{e.diagnostic.message}"
    message += "\n in file #{file}" if file
    raise Ruby2JS::SyntaxError.new(message, e.diagnostic)
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
