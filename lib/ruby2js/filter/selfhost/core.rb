# frozen_string_literal: true

# Selfhost Core Filter - Universal transformations for self-hosting
#
# Note: Most transformations previously here are now handled by:
# - Ruby2JS core: symbols → strings conversion
# - comparison: :identity option: == → ===
# - functions filter: .freeze, negative index assignment, 2-arg slice, .reject
#
# Target-specific transformations are in separate filters:
# - selfhost/walker.rb - private/protected/public removal
# - selfhost/converter.rb - handle :type do...end patterns
# - selfhost/spec.rb - _() wrapper removal, minitest → JS test framework
#
# This file is kept as the entry point for requiring the selfhost filter.
# It registers itself to DEFAULTS but has no transformations of its own.

require 'ruby2js'

module Ruby2JS
  module Filter
    module Selfhost
      module Core
        include SEXP
        # No transformations - all moved to target-specific filters
      end

      # Register the Core module - it's always loaded with selfhost
      DEFAULTS.push Core
    end
  end
end
