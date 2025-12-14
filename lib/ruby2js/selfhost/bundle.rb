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

# ============================================================================
# Initialize Prism at module load time
# ============================================================================

await initPrism()

# ============================================================================
# Convert function using Pipeline
# ============================================================================

# Convert Ruby source to JavaScript
# @param source [String] Ruby source code
# @param options [Object] Optional settings (eslevel, filters, etc.)
# @return [String] JavaScript output
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

  # Build pipeline options
  pipeline_options = options.merge(source: source)

  # Run pipeline (handles filters if provided, converter setup, execution)
  filters = options[:filters] || []
  pipeline = Ruby2JS::Pipeline.new(ast, comments, filters: filters, options: pipeline_options)
  result = pipeline.run
  result.to_s!
end

# Export the Ruby2JS module
export [Ruby2JS]
