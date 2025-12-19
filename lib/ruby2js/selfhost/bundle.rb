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
# Convert function using Pipeline
# ============================================================================

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

  # Run pipeline (handles filters if provided, converter setup, execution)
  filters = options[:filters] || []
  pipeline = Ruby2JS::Pipeline.new(ast, comments, filters: filters, options: pipeline_options)
  result = pipeline.run

  # Set file name for sourcemap generation
  result.file_name = options[:file] if options[:file]

  # Return result object (has .toString() and .sourcemap methods)
  result
end

# Export the Ruby2JS module
# Note: Filter runtime exports are appended by transpile_bundle.rb
export [Ruby2JS]
