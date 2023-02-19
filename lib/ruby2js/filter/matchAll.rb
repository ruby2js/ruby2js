# TODO: This feature is deprecated.

require 'ruby2js'

module Ruby2JS
  module Filter
    module MatchAll
      include SEXP

      # ensure matchAll is before Functions in the filter list
      def self.reorder(filters)
        if \
          defined? Ruby2JS::Filter::Functions and
          filters.include? Ruby2JS::Filter::Functions
        then
          filters = filters.dup
          matchAll = filters.delete(Ruby2JS::Filter::MatchAll)
          filters.insert filters.index(Ruby2JS::Filter::Functions), matchAll
        else
          filters
        end
      end

      def on_block(node)
        return super if es2020

        # only process each/forEach blocks
        call = node.children.first
        return super unless
          [:each, :forEach].include? call.children[1] and
          call.children.first.type == :send and
          node.children[1].children.length == 1

        # only process matchAll requests with simple expressions
        call = call.children.first
        return super unless
          call.children[1] == :matchAll and
          call.children[2].type == :send and
          call.children[2].children.first == nil and
          call.children[2].children.length == 2

        process s(:while,
          s(:lvasgn, node.children[1].children[0].children[0],
            s(:send, call.children[2], :exec, call.children.first)),
          node.children[2])
      end
    end

    DEFAULTS.push MatchAll
  end
end
