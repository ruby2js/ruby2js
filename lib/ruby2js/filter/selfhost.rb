# frozen_string_literal: true

# Selfhost Filter - Orchestrates self-hosting filters for Ruby2JS transpilation
#
# This is the main entry point for self-hosting Ruby2JS to JavaScript.
# It loads the modular filter components:
#
# - selfhost/core.rb     - Universal transformations (always loaded)
# - selfhost/walker.rb   - PrismWalker patterns (for walker transpilation)
# - selfhost/converter.rb - Converter patterns (for converter transpilation)
# - selfhost/spec.rb     - Test spec patterns (for spec transpilation)
#
# Usage:
#   # For walker transpilation:
#   require 'ruby2js/filter/selfhost'  # Loads core + walker
#
#   # Filter chain for walker:
#   filters: [Pragma, Require, Combiner, Selfhost::Core, Selfhost::Walker, Functions, ESM]
#
#   # For converter transpilation (when implemented):
#   filters: [Pragma, Require, Combiner, Selfhost::Core, Selfhost::Converter, Functions, ESM]
#
#   # For spec transpilation (when implemented):
#   filters: [Pragma, Selfhost::Core, Selfhost::Spec, Functions, ESM]
#
# See plans/PRAGMA_SELFHOST.md for the full approach.

require 'ruby2js'

# Load all selfhost filter modules
require_relative 'selfhost/core'
require_relative 'selfhost/walker'
require_relative 'selfhost/converter'
require_relative 'selfhost/spec'

module Ruby2JS
  module Filter
    module Selfhost
      # Re-export the modules for convenient access
      # Usage: Ruby2JS::Filter::Selfhost::Core, etc.
    end
  end
end
