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

# Add Map-compatible methods to Hash for selfhost compatibility.
# JS Map uses .get()/.set() while Ruby Hash uses []. This lets Ruby code
# use .get()/.set() which transpiles directly to working JS Map calls.
class Hash # Pragma: skip
  def get(key) = self[key]
  def set(key, value) = self[key] = value
end

require 'ruby2js/configuration_dsl' unless RUBY_ENGINE == 'opal'
require 'ruby2js/converter'
require 'ruby2js/filter'
require 'ruby2js/filter/processor'
require 'ruby2js/namespace'
require 'ruby2js/pipeline'

# Function is an alias for Proc in Ruby.
# In JavaScript, Function.new { } produces a regular function() instead of an arrow =>.
# Regular functions have dynamic `this` binding, while arrow functions capture `this` lexically.
# Use Function.new when you need dynamic `this` (e.g., for method composition, event handlers).
Function = Proc unless defined?(Function)

module Ruby2JS
  class SyntaxError < RuntimeError
    attr_reader :diagnostic
    def initialize(message, diagnostic=nil)
      super(message)
      @diagnostic = diagnostic
    end
  end

  @@eslevel_default = 2020
  @@eslevel_preset_default = 2022
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
    # DEFAULTS, SEXP module, and Processor class are defined in filter/processor.rb
  end

  def self.convert(source, options={})
    Filter.autoregister unless RUBY_ENGINE == 'opal'
    options = options.dup

    # Handle different source types (Ruby-specific: Proc handling)
    if Proc === source
      file, line = source.source_location
      source = IO.read(file)
      ast, comments = parse(source)
      ast, block_range = find_block(ast, line)
      # Filter _raw comments to only those within the block's source range.
      # This preserves trailing/orphan comments inside the block while
      # excluding comments from the surrounding file.
      if comments.is_a?(Hash) && comments[:_raw] && block_range
        comments[:_raw] = comments[:_raw].select do |comment|
          loc = comment.loc
          if loc.respond_to?(:expression) && loc.expression
            pos = loc.expression.begin_pos
            pos >= block_range[0] && pos <= block_range[1]
          else
            false
          end
        end
      end
      options[:file] ||= file
    elsif source.respond_to?(:type) && source.respond_to?(:children)
      # AST node passed directly (Parser::AST::Node or Ruby2JS::Node)
      ast, comments = source, {}
      source = ""
    else
      ast, comments = parse(source, options[:file])
    end

    # Return empty result for empty source
    if ast.nil?
      ruby2js = Converter.new(ast, comments)
      ruby2js.eslevel = options[:eslevel] || @@eslevel_default
      ruby2js.file_name = options[:file] || ''
      return ruby2js
    end

    # Parse magic comments
    disable_autoimports = false
    disable_autoexports = false
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

    # Load config file (Ruby-specific)
    unless RUBY_ENGINE == 'opal'
      unless options.key?(:config_file) || !File.exist?("config/ruby2js.rb")
        options[:config_file] ||= "config/ruby2js.rb"
      end

      if options[:config_file]
        options = ConfigurationDSL.load_from_file(options[:config_file], options).to_h
      end
    end

    # Apply preset defaults
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

    # Resolve filter modules (Ruby-specific: requires filter files)
    filters = Filter.require_filters(options[:filters] || Filter::DEFAULTS)

    # Ruby-specific: resolve binding/ivars before pipeline
    binding_val = options[:binding]
    ivars = options[:ivars]

    if binding_val and not ivars
      ivars = binding_val.eval \
        'Hash[instance_variables.map {|var| [var, instance_variable_get(var)]}]'
    elsif options[:scope] and not ivars
      scope = options.delete(:scope)
      ivars = Hash[scope.instance_variables.map { |var|
        [var, scope.instance_variable_get(var)] }]
    end

    # Build pipeline options
    pipeline_options = options.merge(
      source: source,
      disable_autoimports: disable_autoimports,
      disable_autoexports: disable_autoexports,
      binding: binding_val,
      ivars: ivars
    )

    # Run pipeline (transpilable orchestration)
    pipeline = Pipeline.new(ast, comments, filters: filters, options: pipeline_options)
    ruby2js = pipeline.run

    # Ruby-specific: timestamp from file modification time
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

  # CommentsMap - just a Hash subclass for type identification
  # In JS selfhost, Map is used instead (for object key support)
  class CommentsMap < Hash # Pragma: skip
  end

  # Associate comments with AST nodes based on position.
  # Each comment attaches to the first eligible node that starts at or after the comment ends.
  # This mimics Parser gem behavior which skips :begin nodes for preceding comments.
  #
  # The JS version in demo/selfhost/shared/runtime.mjs uses Map instead of Hash.
  def self.associate_comments(ast, comments)
    result = CommentsMap.new
    return result if comments.nil? || comments.empty? || ast.nil?

    nodes_by_pos = []

    collect_nodes = proc do |node, depth|
      next unless node

      # Only add node if it has location info
      if node.loc
        start_pos = node.loc.start_offset
        if start_pos && node.type != :begin
          nodes_by_pos << [start_pos, depth, node]
        end
      end

      # Always recurse into children (even if parent has no loc)
      if node.children
        node.children.each do |child|
          collect_nodes.(child, depth + 1) if child.respond_to?(:type) && child.respond_to?(:children)
        end
      end
    end

    collect_nodes.(ast, 0)

    nodes_by_pos.sort_by! { |pos, depth, _node| [pos, depth] }

    comments.each do |comment|
      comment_end = comment.location.end_offset
      candidate = nodes_by_pos.find { |item| item[0] >= comment_end }
      next unless candidate

      node = candidate[2]
      (result[node] ||= []) << comment
    end

    result
  end

  # Wrapper class for Prism comments to provide compatible interface
  class PrismComment
    attr_reader :text, :location
    alias loc location  # Parser gem uses .loc, Prism wrapper uses .location

    def initialize(prism_comment, source, source_buffer = nil)
      @text = prism_comment.location.slice
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

  # Find a block at the given line and return [body_ast, block_range]
  # block_range is [begin_pos, end_pos] of the full block for comment filtering
  def self.find_block(ast, line)
    return [nil, nil] unless ast.respond_to?(:type) && ast.respond_to?(:children)

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
      if node_line == line
        # Return body and the block's source range for comment filtering
        block_range = if loc.respond_to?(:expression) && loc.expression
          [loc.expression.begin_pos, loc.expression.end_pos]
        else
          nil
        end
        return [ast.children.last, block_range]
      end
    end

    ast.children.each do |child|
      if child.respond_to?(:type) && child.respond_to?(:children)
        body, range = find_block(child, line)
        return [body, range] if body
      end
    end

    [nil, nil]
  end
end
