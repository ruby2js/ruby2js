# frozen_string_literal: true

# Selfhost Core Filter - Universal transformations for self-hosting
#
# This filter handles transformations needed by ALL selfhost targets.
#
# Note: Many transformations previously here are now handled by:
# - Ruby2JS core: symbols → strings conversion
# - comparison: :identity option: == → ===
# - functions filter: .freeze, negative index assignment, 2-arg slice, .reject
#
# What remains here:
# - Remove private/protected/public (no-op in JS) - pending discussion
# - Spec mode helpers (gem removal, _() wrapper removal)
#
# Target-specific transformations are in separate filters:
# - selfhost/walker.rb - Prism::Visitor patterns
# - selfhost/converter.rb - handle :type do...end patterns
# - selfhost/spec.rb - minitest → JS test framework

require 'ruby2js'

module Ruby2JS
  module Filter
    module Selfhost
      module Core
        include SEXP

        def initialize(*args)
          super
          @selfhost_spec = false
        end

        def options=(options)
          super
          @selfhost_spec = options[:selfhost_spec]
        end

        def on_send(node)
          target, method, *args = node.children

          # Remove private/protected/public (no-op in JS)
          if target.nil? && [:private, :protected, :public].include?(method) && args.empty?
            return s(:hide)
          end

          # Spec mode: remove gem() calls
          if @selfhost_spec && target.nil? && method == :gem
            return s(:hide)
          end

          # Spec mode: _(...) wrapper → just the inner expression
          if @selfhost_spec && target.nil? && method == :_ && args.length == 1
            return process(args.first)
          end

          super
        end
      end

      # Register the Core module - it's always loaded with selfhost
      DEFAULTS.push Core
    end
  end
end
