# Ruby2JS Self-hosted Library - for CLI see ruby2js-cli.js
#
# This file uses require_relative to inline all necessary sources into a single
# JavaScript module. The Ruby2JS Require filter processes these require_relative
# calls and inlines the actual code content.
#
# The resulting ruby2js.js is a library that can be:
#   - Imported in Node.js: import { convert } from './ruby2js.js'
#   - Imported in browser: import { convert } from './ruby2js.js'
#
# External dependencies: @ruby/prism only

# ============================================================================
# Inline all source files via require_relative
# ============================================================================

# Runtime support classes (source buffer, source range, comments)
# Note: runtime.rb imports @ruby/prism, so we don't need to import it here
require_relative 'runtime'

# Namespace tracking for class/module scope
require_relative '../../ruby2js/namespace'

# Inflector for singularize/pluralize (used by Rails filters)
require_relative '../../ruby2js/inflector'

# AST node representation
require_relative '../../ruby2js/node'

# Set up globals (including Ruby2JS.Node) before walker needs them
setupGlobals(Ruby2JS)

# Prism AST walker (converts Prism AST to Parser-compatible format)
require_relative '../../ruby2js/prism_walker'

# Serializer (output formatting) - must come before Converter
require_relative '../../ruby2js/serializer'

# Converter (main conversion logic + all handlers)
require_relative '../../ruby2js/converter'

# Filter Processor (AST walker, SEXP helpers, type aliasing)
require_relative '../../ruby2js/filter/processor'

# Pipeline (orchestration: filters + converter)
require_relative '../../ruby2js/pipeline'

# JSX parser (converts JSX syntax to Ruby DSL for RBX files)
require_relative '../../ruby2js/jsx'

# Regexp Scanner (minimal regex group parsing for selfhost filters)
# Inlined directly to avoid require_relative processing issues
def scanRegexpGroups(pattern)
  tokens = []
  stack = []
  i = 0

  while i < pattern.length
    char = pattern[i]

    if char == '\\'
      i += 2
    elsif char == '['
      i += 1
      while i < pattern.length && pattern[i] != ']'
        i += 1 if pattern[i] == '\\'
        i += 1
      end
      i += 1
    elsif char == '('
      if pattern[i + 1] != '?'
        token = [:group, :capture, "(", i, nil]
        tokens << token
        stack << token
      else
        stack << nil
      end
      i += 1
    elsif char == ')'
      group = stack.pop()
      if group
        group[4] = i + 1
        tokens << [:group, :close, ")", i, i + 1]
      end
      i += 1
    else
      i += 1
    end
  end

  return tokens
end

# ============================================================================
# Initialize Prism at module load time
# ============================================================================

await initPrism()

# ============================================================================
# Parse and Convert functions using Pipeline
# ============================================================================

# Parse Ruby source to AST
# @param source [String] Ruby source code
# @param file [String] Optional file name
# @return [Array] [ast, comments_hash] - matches Ruby's Ruby2JS.parse signature
export def parse(source, file=nil)
  prism_parse = getPrismParse()
  parse_result = prism_parse(source)

  if parse_result.errors && parse_result.errors.length > 0
    raise parse_result.errors[0].message
  end

  walker = Ruby2JS::PrismWalker.new(source, file)
  ast = walker.visit(parse_result.value)

  # Associate comments with AST nodes (matches Ruby's parse return format)
  source_buffer = walker.source_buffer
  wrapped_comments = (parse_result.comments || []).map do |c|
    PrismComment.new(c, source, source_buffer)
  end
  comments = associateComments(ast, wrapped_comments)
  comments.set("_raw", wrapped_comments)

  [ast, comments]
end

# Convert Ruby source to JavaScript
# @param source [String] Ruby source code
# @param options [Object] Optional settings (eslevel, filters, file, etc.)
# @return [Serializer] Result object with .toString() and .sourcemap methods
export def convert(source, options = {})
  prism_parse = getPrismParse()
  parse_result = prism_parse(source)

  if parse_result.errors && parse_result.errors.length > 0
    raise parse_result.errors[0].message
  end

  # Extract template from __END__ data section if present
  template = nil
  if parse_result.dataLoc
    template_raw = source[parse_result.dataLoc.startOffset, parse_result.dataLoc.length]
    template = template_raw.sub(/\A__END__\r?\n?/, '')
  end

  walker = Ruby2JS::PrismWalker.new(source, options[:file])
  ast = walker.visit(parse_result.value)

  # Associate comments with AST nodes
  source_buffer = walker.source_buffer
  wrapped_comments = (parse_result.comments || []).map do |c|
    PrismComment.new(c, source, source_buffer)
  end
  comments = associateComments(ast, wrapped_comments)
  # Store raw comments for reassociate_comments (matches Ruby pipeline)
  comments.set("_raw", wrapped_comments)

  # Build pipeline options
  pipeline_options = options.merge(source: source)

  # Resolve filter names to filter objects
  # Filters can be passed as strings ('Phlex') or as filter objects directly
  # Try exact match first, then capitalized (e.g., 'lit' -> 'Lit'), then uppercase (e.g., 'esm' -> 'ESM')
  filters = (options[:filters] || []).map do |f|
    if f.is_a?(String)
      resolved = Ruby2JS::Filter[f]
      # Try capitalized if exact match fails (e.g., 'lit' -> 'Lit')
      unless resolved
        capitalized = f[0].upcase + f[1..-1]
        resolved = Ruby2JS::Filter[capitalized]
      end
      # Try all-caps for acronyms like ESM, CJS
      unless resolved
        resolved = Ruby2JS::Filter[f.upcase]
      end
      unless resolved
        raise "Filter #{f} not loaded. Load it via run_all_specs.mjs or import manually."
      end
      resolved
    else
      f
    end
  end

  # Run pipeline (handles filters if provided, converter setup, execution)
  pipeline = Ruby2JS::Pipeline.new(ast, comments, filters: filters, options: pipeline_options)
  result = pipeline.run

  # Record timestamps for cache invalidation (used by Vite dev server)
  result.timestamp(options[:file]) if options[:file]

  # Set file name for sourcemap generation
  result.file_name = options[:file] if options[:file]

  # Set template if extracted and option specified
  result.template = template if options[:template] && template

  # Return result object (has .toString() and .sourcemap methods)
  result
end

# Export the Ruby2JS module
# Note: Filter runtime exports are appended by transpile_bundle.rb
export [Ruby2JS]
