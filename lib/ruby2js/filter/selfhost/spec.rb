# frozen_string_literal: true

# Selfhost Spec Filter - Transformations for test spec transpilation
#
# Currently handles:
# - _(...) wrapper removal (minitest expectation syntax)
#
# Future patterns to handle:
# - describe X do...end → describe('X', () => {...})
# - it 'text' do...end → it('text', () => {...})
# - before do...end → beforeEach(() => {...})
# - Minitest assertions: must_equal, must_be_nil, etc.

require 'ruby2js'

module Ruby2JS
  module Filter
    module Selfhost
      module Spec
        include SEXP

        def on_send(node)
          target, method, *args = node.children

          # _(...) wrapper → just the inner expression
          # Minitest uses _() to wrap values for expectation syntax
          if target.nil? && method == :_ && args.length == 1
            return process(args.first)
          end

          super
        end
      end

      # NOTE: Spec is NOT added to DEFAULTS - it's loaded explicitly
      # when transpiling spec files
    end
  end
end
