require 'ruby2js'
require 'set'

module Ruby2JS
  module Filter
    module Pragma
      include SEXP

      # Mapping from pragma comment text to internal symbol
      PRAGMAS = {
        '??' => :nullish,
        'nullish' => :nullish,
        'noes2015' => :noes2015,
        'function' => :noes2015,
        'guard' => :guard
      }.freeze

      def initialize(*args)
        super
        @pragmas = {}
        @pragma_scanned = false
      end

      def options=(options)
        super
        @pragmas = {}
        @pragma_scanned = false
      end

      # Scan all comments for pragma patterns and build line => Set<pragma> map
      def scan_pragmas
        return if @pragma_scanned
        @pragma_scanned = true

        # Get raw comments from the comments hash
        raw_comments = @comments[:_raw] || []

        raw_comments.each do |comment|
          text = comment.respond_to?(:text) ? comment.text : comment.to_s

          # Match "# Pragma: <name>" pattern (case insensitive)
          if text =~ /#\s*Pragma:\s*(\S+)/i
            pragma_name = $1
            pragma_sym = PRAGMAS[pragma_name]

            if pragma_sym
              # Get the line number of the comment
              line = if comment.respond_to?(:loc) && comment.loc.respond_to?(:line)
                comment.loc.line
              elsif comment.respond_to?(:location)
                loc = comment.location
                loc.respond_to?(:start_line) ? loc.start_line : loc.line
              else
                next
              end

              @pragmas[line] ||= Set.new
              @pragmas[line] << pragma_sym
            end
          end
        end
      end

      # Check if a node's line has a specific pragma
      def pragma?(node, pragma_sym)
        scan_pragmas

        line = node_line(node)
        return false unless line

        @pragmas[line]&.include?(pragma_sym)
      end

      # Get the line number for a node
      def node_line(node)
        return nil unless node.respond_to?(:loc) && node.loc

        loc = node.loc
        if loc.respond_to?(:line)
          loc.line
        elsif loc.respond_to?(:expression) && loc.expression
          loc.expression.line
        elsif loc.is_a?(Hash) && loc[:start_line]
          loc[:start_line]
        end
      end

      # Handle || with nullish pragma -> ??
      def on_or(node)
        if pragma?(node, :nullish) && es2020
          process s(:nullish_or, *node.children)
        else
          super
        end
      end

      # Handle ||= with nullish pragma -> ??=
      # Note: We check es2020 here because ?? is available then.
      # The converter will decide whether to use ??= (ES2021+) or expand to a = a ?? b
      def on_or_asgn(node)
        if pragma?(node, :nullish) && es2020
          process s(:nullish_asgn, *node.children)
        else
          super
        end
      end

      # Handle blocks/lambdas with noes2015 pragma -> force function syntax
      def on_block(node)
        call, args, body = node.children

        if pragma?(node, :noes2015)
          # Transform to use :deff which forces function syntax
          function = node.updated(:deff, [nil, args, body])
          process s(call.type, *call.children, function)
        else
          super
        end
      end

      # Handle def (anonymous functions) with noes2015 pragma
      def on_def(node)
        if node.children[0].nil? && pragma?(node, :noes2015)
          # Convert anonymous def to deff (forces function syntax)
          # Don't re-process - just update type and process children
          node.updated(:deff, process_all(node.children))
        else
          super
        end
      end

      # Pass through deff nodes without re-triggering pragma checks
      def on_deff(node)
        process_children(node)
      end

      # Handle array splat with guard pragma -> ensure array even if null
      # [*a] with guard pragma becomes (a ?? [])
      def on_array(node)
        if pragma?(node, :guard) && es2020
          items = node.children
          changed = false

          # Look for splat nodes
          guarded_items = items.map do |item|
            if ast_node?(item) && item.type == :splat && item.children.first
              # Replace splat contents with (contents ?? [])
              inner = item.children.first
              guarded = s(:begin, s(:nullish_or, inner, s(:array)))
              changed = true
              s(:splat, guarded)
            else
              item
            end
          end

          if changed
            # Process the guarded items, then return without re-checking pragma
            node.updated(nil, process_all(guarded_items))
          else
            super
          end
        else
          super
        end
      end
    end

    DEFAULTS.push Pragma
  end
end
