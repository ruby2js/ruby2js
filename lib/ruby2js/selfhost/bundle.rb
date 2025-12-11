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

# CLI for command-line usage
require_relative 'cli'

# Export the Ruby2JS module
export [Ruby2JS]
