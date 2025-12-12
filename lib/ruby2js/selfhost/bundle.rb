# Ruby2JS Self-hosted Bundle
#
# This file uses require_relative to inline all necessary sources into a single
# JavaScript module. The Ruby2JS Require filter processes these require_relative
# calls and inlines the actual code content.
#
# The resulting ruby2js.mjs can be:
#   - Run as a CLI: node ruby2js.mjs [options] [file]
#   - Imported in browser: import { convert } from './ruby2js.mjs'
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

# ============================================================================
# Initialize Prism at module load time
# ============================================================================

await initPrism()

# ============================================================================
# Simple convert function for easy usage
# ============================================================================

# Convert Ruby source to JavaScript
# @param source [String] Ruby source code
# @param options [Object] Optional settings (eslevel, underscored_private, etc.)
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

  # Create and run converter
  converter = Ruby2JS::Converter.new(ast, comments, options)
  converter.eslevel = options[:eslevel] || 2022
  converter.comparison = options[:comparison] if options[:comparison]
  converter.or = options[:or] if options[:or]
  converter.strict = options[:strict] if options[:strict]
  converter.underscored_private = options[:underscored_private] if options[:underscored_private]
  converter.namespace = Ruby2JS::Namespace.new

  # Enable vertical whitespace if source has newlines
  converter.enable_vertical_whitespace if source.include?("\n")

  converter.convert
  converter.to_s!
end

# CLI for command-line usage (must come after convert() is defined)
require_relative 'cli'

# Export the Ruby2JS module
export [Ruby2JS]
