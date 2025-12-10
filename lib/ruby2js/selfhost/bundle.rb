# Ruby2JS Self-hosted Bundle Entry Point (Node.js CLI)
# This is the main entry point that re-exports everything needed for the CLI.
# Each module is transpiled separately; this file just ties them together.
#
# Note: prism_browser.mjs is NOT included here - it's for browser use only.
# The runtime.mjs imports @ruby/prism directly which works for Node.js.

# Runtime classes (PrismSourceBuffer, PrismSourceRange, Prism, etc.)
export "*", from: './runtime.mjs'

# Core modules
export "*", from: './namespace.mjs'
export "*", from: './walker.mjs'
export "*", from: './converter.mjs'
