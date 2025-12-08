# frozen_string_literal: true

# Selfhost Walker Filter - Transformations specific to PrismWalker transpilation
#
# Most transformations have been moved to general-purpose filters:
# - Functions filter: .freeze, .to_sym, .reject, negative index, 2-arg slice, .empty?
# - Pragma filter: # Pragma: skip for require/def/alias
# - Return filter: autoreturn for method bodies
#
# What remains here:
# - Remove private/protected/public (walker source uses these but JS doesn't need them,
#   and Ruby2JS core raises an error for these in classes)

require 'ruby2js'

module Ruby2JS
  module Filter
    module Selfhost
      module Walker
        include SEXP

        def on_send(node)
          target, method, *args = node.children

          # Remove private/protected/public (no-op in JS)
          # Ruby2JS core raises an error for these in classes, but walker source uses them
          if target.nil? && [:private, :protected, :public].include?(method) && args.empty?
            return s(:hide)
          end

          super
        end
      end

      # Register Walker module
      DEFAULTS.push Walker
    end
  end
end
