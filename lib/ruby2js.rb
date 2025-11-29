# Determine which parser to use:
# - RUBY2JS_PARSER=prism       - use direct Prism walker (Ruby 3.4+, no parser gem dependency)
# - RUBY2JS_PARSER=translation - use Prism via Translation::Parser (requires parser gem)
# - RUBY2JS_PARSER=parser      - force whitequark parser gem
# - unset                      - auto-detect based on Ruby version:
#                                Ruby 3.4+: Prism walker (direct)
#                                Ruby 3.3:  Prism translation layer
#                                Ruby <3.3: parser gem
#
# Note: Opal always uses the parser gem (no Prism support in browser)
if RUBY_ENGINE == 'opal'
  require 'parser/current'
  RUBY2JS_PARSER = :parser
else
  case ENV['RUBY2JS_PARSER']
  when 'prism'
    require 'prism'
    require 'ruby2js/prism_walker'
    RUBY2JS_PARSER = :prism
  when 'translation'
    require 'prism'
    require 'prism/translation/parser'
    require 'parser/current'
    RUBY2JS_PARSER = :translation
  when 'parser'
    old_verbose, $VERBOSE = $VERBOSE, nil
    require 'parser/current'
    $VERBOSE = old_verbose
    RUBY2JS_PARSER = :parser
  else
    # Auto-detect based on Ruby version
    # Ruby 3.4+: use direct Prism walker (stable API)
    # Ruby 3.3: use Prism translation layer (handles API differences)
    # Ruby <3.3: use parser gem
    ruby_version = Gem::Version.new(RUBY_VERSION)
    if ruby_version >= Gem::Version.new('3.4')
      begin
        require 'prism'
        require 'ruby2js/prism_walker'
        RUBY2JS_PARSER = :prism
      rescue LoadError
        old_verbose, $VERBOSE = $VERBOSE, nil
        require 'parser/current'
        $VERBOSE = old_verbose
        RUBY2JS_PARSER = :parser
      end
    elsif ruby_version >= Gem::Version.new('3.3')
      begin
        require 'prism'
        require 'prism/translation/parser'
        require 'parser/current'
        RUBY2JS_PARSER = :translation
      rescue LoadError
        old_verbose, $VERBOSE = $VERBOSE, nil
        require 'parser/current'
        $VERBOSE = old_verbose
        RUBY2JS_PARSER = :parser
      end
    else
      old_verbose, $VERBOSE = $VERBOSE, nil
      require 'parser/current'
      $VERBOSE = old_verbose
      RUBY2JS_PARSER = :parser
    end
  end
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

  # Check if object is an AST node (works with both Parser::AST::Node and Ruby2JS::Node)
  def self.ast_node?(obj)
    obj.respond_to?(:type) && obj.respond_to?(:children) && obj.respond_to?(:updated)
  end

  module Filter
    DEFAULTS = []

    module SEXP
      # construct an AST Node
      def s(type, *args)
        if defined?(Parser::AST::Node)
          Parser::AST::Node.new(type, args)
        else
          Ruby2JS::Node.new(type, args)
        end
      end

      # For compatibility - some code uses S() to update @ast
      def S(type, *args)
        @ast.updated(type, args)
      end

      # Check if object is an AST node (works with both Parser::AST::Node and Ruby2JS::Node)
      def ast_node?(obj)
        Ruby2JS.ast_node?(obj)
      end
    end

    # Processor walks Ruby2JS AST and dispatches to on_<type> methods
    class Processor
      include Ruby2JS::Filter
      BINARY_OPERATORS = Converter::OPERATORS[2..-1].flatten

      attr_accessor :prepend_list, :disable_autoimports, :disable_autoexports, :namespace

      def initialize(comments)
        @comments = comments
        @ast = nil
        @exclude_methods = []
        @prepend_list = Set.new
      end

      # Check if object is an AST node (works with both Parser::AST::Node and Ruby2JS::Node)
      def ast_node?(obj)
        Ruby2JS.ast_node?(obj)
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

      def es2023
        @options[:eslevel] >= 2023
      end

      def es2024
        @options[:eslevel] >= 2024
      end

      def es2025
        @options[:eslevel] >= 2025
      end

      # Process a node by dispatching to on_<type> method
      def process(node)
        return node unless ast_node?(node)

        ast, @ast = @ast, node

        # Dispatch to handler method
        handler = "on_#{node.type}"
        if respond_to?(handler)
          replacement = send(handler, node)
        else
          # Default: process children
          replacement = process_children(node)
        end

        replacement
      ensure
        @ast = ast
      end

      # Process all children of a node, returning updated node if any changed
      def process_children(node)
        return node unless ast_node?(node)

        new_children = node.children.map do |child|
          if ast_node?(child)
            process(child)
          else
            child
          end
        end

        if new_children != node.children
          node.updated(nil, new_children)
        else
          node
        end
      end

      # Helper to create nodes
      def s(type, *children)
        if defined?(Parser::AST::Node)
          Parser::AST::Node.new(type, children)
        else
          Ruby2JS::Node.new(type, children)
        end
      end

      # Process all children of a node (like process_children but returns array)
      def process_all(nodes)
        return [] if nodes.nil?
        nodes.map { |node| process(node) }
      end

      # handle all of the 'invented/synthetic' ast types
      def on_assign(node); process_children(node); end
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
      def on_defineProps(node); process_children(node); end
      def on_hide(node); on_begin(node); end
      def on_xnode(node); process_children(node); end
      def on_export(node); process_children(node); end
      def on_import(node); process_children(node); end
      def on_taglit(node); on_pair(node); end

      # Default handlers that process children
      def on_nil(node); node; end
      def on_sym(node); node; end
      def on_int(node); node; end
      def on_float(node); node; end
      def on_str(node); node; end
      def on_true(node); node; end
      def on_false(node); node; end
      def on_self(node); node; end

      # Handlers that process children by default
      # Note: send and csend are explicitly defined below with special handling
      %i[
        lvar ivar cvar gvar const
        lvasgn ivasgn cvasgn gvasgn casgn
        block def defs class module
        if case when while until for
        and or not
        array hash pair splat kwsplat
        args arg optarg restarg kwarg kwoptarg kwrestarg blockarg
        return break next redo retry
        begin kwbegin rescue resbody ensure
        masgn mlhs
        op_asgn and_asgn or_asgn
        regexp regopt
        dstr dsym xstr
        yield super zsuper
        defined? alias undef
        irange erange
        sclass
        match_pattern match_var
      ].each do |type|
        define_method("on_#{type}") do |node|
          process_children(node)
        end unless method_defined?("on_#{type}")
      end

      # convert numbered parameters block to a normal block
      def on_numblock(node)
        call, count, block = node.children

        process s(:block,
          call,
          s(:args, *((1..count).map {|i| s(:arg, :"_#{i}")})),
          block
        )
      end

      # convert map(&:symbol) to a block
      def on_send(node)
        node = process_children(node)
        return node unless ast_node?(node) && [:send, :csend].include?(node.type)

        if node.children.length > 2 and
           ast_node?(node.children.last) and
           node.children.last.type == :block_pass
          block_pass = node.children.last
          if ast_node?(block_pass.children.first) &&
             block_pass.children.first.type == :sym
            method = block_pass.children.first.children.first
            # preserve csend type for optional chaining
            call_type = node.type == :csend ? :csend : :send
            if BINARY_OPERATORS.include?(method)
              return on_block s(:block, s(call_type, *node.children[0..-2]),
                s(:args, s(:arg, :a), s(:arg, :b)), s(:return,
                process(s(:send, s(:lvar, :a), method, s(:lvar, :b)))))
            else
              return on_block s(:block, s(call_type, *node.children[0..-2]),
                s(:args, s(:arg, :item)), s(:return,
                process(s(:attr, s(:lvar, :item), method))))
            end
          end
        end
        node
      end

      def on_csend(node)
        on_send(node)
      end
    end
  end

  def self.convert(source, options={})
    Filter.autoregister unless RUBY_ENGINE == 'opal'
    options = options.dup

    if Proc === source
      file, line = source.source_location
      source = IO.read(file)
      ast, comments = parse(source)
      ast = find_block(ast, line)
      options[:file] ||= file
    elsif source.respond_to?(:type) && source.respond_to?(:children)
      # AST node passed directly (Parser::AST::Node or Ruby2JS::Node)
      ast, comments = source, {}
      source = ""
    else
      ast, comments = parse(source, options[:file])
    end

    # check if magic comment is present
    raw_comments = comments[:_raw] || []
    first_comment = raw_comments.first
    if first_comment
      comment_text = first_comment.respond_to?(:text) ? first_comment.text : first_comment.to_s
      if comment_text.include?(" ruby2js: preset")
        options[:preset] = true
        if comment_text.include?("filters: ")
          options[:filters] = comment_text.match(%r(filters:\s*?([^\s]+)\s?.*$))[1].split(",").map(&:to_sym)
        end
        if comment_text.include?("eslevel: ")
          options[:eslevel] = comment_text.match(%r(eslevel:\s*?([^\s]+)\s?.*$))[1].to_i
        end
        if comment_text.include?("disable_filters: ")
          options[:disable_filters] = comment_text.match(%r(disable_filters:\s*?([^\s]+)\s?.*$))[1].split(",").map(&:to_sym)
        end
      end
      disable_autoimports = comment_text.include?(" autoimports: false")
      disable_autoexports = comment_text.include?(" autoexports: false")
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
        filter = Class.new(filter) { include mod }
      end
      filter = filter.new(comments)

      filter.disable_autoimports = disable_autoimports
      filter.disable_autoexports = disable_autoexports
      filter.options = filter_options
      filter.namespace = namespace
      ast = filter.process(ast)

      # Re-associate comments with filtered AST (filters may create new node objects)
      # This may fail if the AST contains synthetic nodes without location info,
      # in which case we fall back to the original (possibly stale) comments hash
      raw_comments = comments[:_raw]
      if raw_comments && !raw_comments.empty?
        begin
          if defined?(Parser::Source::Comment)
            new_comments = Parser::Source::Comment.associate(ast, raw_comments)
          else
            # For prism-direct, use our own association method
            new_comments = associate_comments(ast, raw_comments)
          end
          # Only update if we found associations; otherwise keep original
          # (transformed AST may lack location info entirely)
          if new_comments && !new_comments.empty?
            comments.clear
            comments.merge!(new_comments)
            comments[:_raw] = raw_comments
          end
        rescue NoMethodError
          # Synthetic nodes without location info cause associate to fail
          # Keep original comments hash, which may not associate properly
        end
      end

      unless filter.prepend_list.empty?
        prepend = filter.prepend_list.sort_by { |ast| ast.type == :import ? 0 : 1 }
        prepend.reject! { |ast| ast.type == :import } if filter.disable_autoimports
        if defined?(Parser::AST::Node)
          ast = Parser::AST::Node.new(:begin, [*prepend, ast])
        else
          ast = Ruby2JS::Node.new(:begin, [*prepend, ast])
        end
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
      ruby2js.ivars = Hash[scope.instance_variables.map { |var|
        [var, scope.instance_variable_get(var)] }]
    end

    ruby2js.width = options[:width] if options[:width]

    ruby2js.enable_vertical_whitespace if source.include? "\n"

    ruby2js.convert

    ruby2js.timestamp options[:file]

    ruby2js.file_name = options[:file] || ''

    ruby2js
  end

  def self.parse(source, file=nil, line=1)
    case RUBY2JS_PARSER
    when :prism
      parse_with_prism(source, file, line)
    when :translation
      parse_with_translation(source, file, line)
    else
      parse_with_parser(source, file, line)
    end
  end

  # Parse using Prism directly with our custom walker (default, no parser gem dependency)
  def self.parse_with_prism(source, file=nil, line=1)
    source = source.encode('UTF-8')

    result = Prism.parse(source, filepath: file || '(string)')

    if result.failure?
      # Get first error
      error = result.errors.first
      loc = error.location
      message = "line #{loc.start_line}, column #{loc.start_column}: #{error.message}"
      message += "\n in file #{file}" if file
      raise Ruby2JS::SyntaxError.new(message)
    end

    walker = Ruby2JS::PrismWalker.new(source, file)
    ast = walker.visit(result.value)

    # Convert Prism comments to wrapper objects, using shared source_buffer for matching
    raw_comments = result.comments.map do |comment|
      PrismComment.new(comment, source, walker.source_buffer)
    end

    # Associate comments with AST nodes
    comments_hash = associate_comments(ast, raw_comments)
    comments_hash[:_raw] = raw_comments

    [ast, comments_hash]
  end

  # Parse using Prism's Translation::Parser layer (requires parser gem)
  def self.parse_with_translation(source, file=nil, line=1)
    buffer = Parser::Source::Buffer.new(file || '(string)')
    buffer.source = source.encode('UTF-8')

    parser = Prism::Translation::Parser.new
    begin
      ast, comments = parser.parse_with_comments(buffer)
    rescue Parser::SyntaxError => e
      raise Ruby2JS::SyntaxError.new(e.message, e.diagnostic)
    end

    # Associate comments with AST nodes (same format as parser gem)
    comments_hash = Parser::Source::Comment.associate(ast, comments)

    # Store raw comments for filters that may need them (e.g., for magic comments)
    comments_hash[:_raw] = comments

    [ast, comments_hash]
  end

  # Associate comments with AST nodes (similar to Parser::Source::Comment.associate)
  # Each comment attaches to the first eligible node that starts at or after the comment ends.
  # This mimics Parser gem behavior which skips :begin nodes for preceding comments.
  def self.associate_comments(ast, comments)
    return {} if comments.empty? || ast.nil?

    # Collect all nodes with their start positions and depth
    # Skip :begin nodes for comment association (matching Parser gem behavior)
    nodes_by_pos = []
    collect_nodes = lambda do |node, depth = 0|
      return unless node.respond_to?(:loc) && node.loc
      start_pos = if node.loc.respond_to?(:start_offset)
        node.loc.start_offset
      elsif node.loc.respond_to?(:expression) && node.loc.expression
        node.loc.expression.begin_pos
      elsif node.loc.is_a?(Hash) && node.loc[:start_offset]
        node.loc[:start_offset]
      end

      # Skip :begin nodes for comment association (Parser gem skips these)
      nodes_by_pos << [start_pos, depth, node] if start_pos && node.type != :begin

      node.children.each do |child|
        collect_nodes.call(child, depth + 1) if child.respond_to?(:type) && child.respond_to?(:children)
      end
    end
    collect_nodes.call(ast)

    # Sort nodes by start position, then by depth (shallower first for same position)
    nodes_by_pos.sort_by! { |pos, depth, _| [pos, depth] }

    # Associate each comment with the first eligible node that starts at or after comment ends
    result = {}
    comments.each do |comment|
      comment_end = comment.location.end_offset

      # Find nodes that start at or after comment ends
      candidates = nodes_by_pos.select { |pos, _, _| pos >= comment_end }
      next if candidates.empty?

      # Get minimum position
      min_pos = candidates.first[0]

      # Among nodes at minimum position, pick the first one (shallower due to sorting)
      node = candidates.find { |pos, _, _| pos == min_pos }&.last
      next unless node

      result[node] ||= []
      result[node] << comment
    end

    result
  end

  # Wrapper class for Prism comments to provide compatible interface
  class PrismComment
    attr_reader :text, :location
    alias loc location  # Parser gem uses .loc, Prism wrapper uses .location

    def initialize(prism_comment, source, source_buffer = nil)
      @text = source[prism_comment.location.start_offset...prism_comment.location.end_offset]
      @location = PrismLocation.new(prism_comment.location, source, source_buffer)
    end

    def to_s
      @text
    end
  end

  # Wrapper for Prism location to provide line/column info
  class PrismLocation
    attr_reader :expression

    def initialize(prism_loc, source, source_buffer = nil)
      @prism_loc = prism_loc
      @source = source
      @source_buffer = source_buffer || PrismSourceBuffer.new(source)
      @expression = PrismSourceRange.new(@source_buffer, prism_loc.start_offset, prism_loc.end_offset)
    end

    def line
      @prism_loc.start_line
    end

    def column
      @prism_loc.start_column
    end

    def start_offset
      @prism_loc.start_offset
    end

    def end_offset
      @prism_loc.end_offset
    end
  end

  # Minimal source buffer for Prism locations (provides source for comment lookup)
  class PrismSourceBuffer
    attr_reader :source, :name

    def initialize(source, name = nil)
      @source = source
      @name = name || ''
      # Build line offset table for line_for_position
      @line_offsets = [0]
      source.each_char.with_index do |char, i|
        @line_offsets << (i + 1) if char == "\n"
      end
    end

    # For equality comparison in comment association
    def ==(other)
      other.is_a?(PrismSourceBuffer) && @source.object_id == other.source.object_id
    end
    alias eql? ==

    def hash
      @source.object_id.hash
    end

    # Return line number (1-based) for a character position
    def line_for_position(pos)
      @line_offsets.bsearch_index { |offset| offset > pos } || @line_offsets.length
    end

    # Return column number (0-based) for a character position
    def column_for_position(pos)
      line_idx = (@line_offsets.bsearch_index { |offset| offset > pos } || @line_offsets.length) - 1
      pos - @line_offsets[line_idx]
    end
  end

  # Minimal source range for Prism locations (provides begin_pos/end_pos for comment lookup)
  class PrismSourceRange
    attr_reader :source_buffer, :begin_pos, :end_pos

    def initialize(source_buffer, begin_pos, end_pos)
      @source_buffer = source_buffer
      @begin_pos = begin_pos
      @end_pos = end_pos
    end

    # Return the source text for this range (like Parser::Source::Range#source)
    def source
      @source_buffer.source[@begin_pos...@end_pos]
    end

    # Return line number (1-based) for start of range
    def line
      @source_buffer.line_for_position(@begin_pos)
    end

    # Return column number (0-based) for start of range
    def column
      @source_buffer.column_for_position(@begin_pos)
    end
  end

  # Parse using whitequark parser gem (Ruby < 3.3 or when Prism unavailable)
  def self.parse_with_parser(source, file=nil, line=1)
    buffer = Parser::Source::Buffer.new(file, line)
    buffer.source = source.encode('UTF-8')

    parser = Parser::CurrentRuby.new
    parser.diagnostics.all_errors_are_fatal = true
    parser.diagnostics.consumer = lambda {|diagnostic| nil}
    parser.builder.emit_file_line_as_literals = false

    begin
      ast, comments = parser.parse_with_comments(buffer)
    rescue Parser::SyntaxError => e
      split = source[0..e.diagnostic.location.begin_pos].split("\n")
      line, col = split.length, split.last.length
      message = "line #{line}, column #{col}: #{e.diagnostic.message}"
      message += "\n in file #{file}" if file
      raise Ruby2JS::SyntaxError.new(message, e.diagnostic)
    end

    # Associate comments with AST nodes
    comments_hash = ast ? Parser::Source::Comment.associate(ast, comments) : {}

    # Store raw comments for filters that may need them
    comments_hash[:_raw] = comments

    [ast, comments_hash]
  end

  def self.find_block(ast, line)
    return nil unless ast.respond_to?(:type) && ast.respond_to?(:children)

    if ast.type == :block
      loc = ast.loc
      # Handle both Parser::AST::Node locations and our simpler hash format
      node_line = if loc.respond_to?(:expression)
        loc.expression&.line
      elsif loc.is_a?(Hash) && loc[:start_offset]
        # For prism-direct, we'd need to convert offset to line
        # For now, skip this comparison - this is mainly used for Proc parsing
        nil
      else
        nil
      end
      return ast.children.last if node_line == line
    end

    ast.children.each do |child|
      if child.respond_to?(:type) && child.respond_to?(:children)
        block = find_block(child, line)
        return block if block
      end
    end

    nil
  end
end
