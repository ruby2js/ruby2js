require 'ruby2js'
require 'set'

module Ruby2JS
  module Filter
    module Pragma
      include SEXP

      # Ensure pragma runs before functions and esm filters so that
      # pragmas like skip, entries, method are processed first
      def self.reorder(filters)
        dominated = [
          defined?(Ruby2JS::Filter::Functions) ? Ruby2JS::Filter::Functions : nil,
          defined?(Ruby2JS::Filter::ESM) ? Ruby2JS::Filter::ESM : nil
        ].compact.select { |f| filters.include?(f) }

        return filters if dominated.empty?

        filters = filters.dup
        pragma = filters.delete(Ruby2JS::Filter::Pragma)

        # Find the earliest position of any dominated filter
        earliest_index = dominated.map { |f| filters.index(f) }.min
        filters.insert(earliest_index, pragma)

        filters
      end

      # Mapping from pragma comment text to internal symbol
      PRAGMAS = {
        '??' => :nullish,
        'nullish' => :nullish,
        '||' => :logical,
        'logical' => :logical,       # || stays as || (for boolean false handling)
        'noes2015' => :noes2015,
        'function' => :noes2015,
        'guard' => :guard,
        # Type disambiguation pragmas
        'array' => :array,
        'hash' => :hash,
        'string' => :string,
        # Behavior pragmas
        'method' => :method,         # proc.call → fn()
        'self' => :self_pragma,      # self → this (avoid conflict with :self)
        'proto' => :proto,           # .class → .constructor
        'entries' => :entries,       # Object.entries for hash iteration
        # Statement control pragmas
        'skip' => :skip              # skip statement (require, def, defs, alias)
      }.freeze

      def initialize(*args)
        super
        @pragmas = {}
        @pragma_scanned_count = 0
      end

      def options=(options)
        super
        @pragmas = {}
        @pragma_scanned_count = 0
      end

      # Scan all comments for pragma patterns and build [source, line] => Set<pragma> map
      # Re-scans when new comments are added (e.g., from require filter merging files)
      # Uses both source buffer name and line number to avoid collisions across files
      def scan_pragmas
        raw_comments = @comments[:_raw] || []
        return if raw_comments.length == @pragma_scanned_count

        # Process only new comments (from index @pragma_scanned_count onwards)
        raw_comments[@pragma_scanned_count..].each do |comment|
          text = comment.respond_to?(:text) ? comment.text : comment.to_s

          # Match "# Pragma: <name>" pattern (case insensitive)
          if text =~ /#\s*Pragma:\s*(\S+)/i
            pragma_name = $1
            pragma_sym = PRAGMAS[pragma_name]

            if pragma_sym
              # Get the source buffer name and line number of the comment
              source_name = nil
              line = nil

              if comment.respond_to?(:loc) && comment.loc
                loc = comment.loc
                if loc.respond_to?(:expression) && loc.expression
                  source_name = loc.expression.source_buffer&.name
                  line = loc.line
                elsif loc.respond_to?(:line)
                  line = loc.line
                end
              elsif comment.respond_to?(:location)
                loc = comment.location
                line = loc.respond_to?(:start_line) ? loc.start_line : loc.line
                # Try to get source buffer name from location
                if loc.respond_to?(:source_buffer)
                  source_name = loc.source_buffer&.name
                end
              end

              next unless line

              # Use [source_name, line] as key to avoid cross-file collisions
              key = [source_name, line]
              @pragmas[key] ||= Set.new
              @pragmas[key] << pragma_sym
            end
          end
        end

        @pragma_scanned_count = raw_comments.length
      end

      # Check if a node's line has a specific pragma
      def pragma?(node, pragma_sym)
        scan_pragmas

        source_name, line = node_source_and_line(node)
        return false unless line

        # Try with source name first, then fall back to nil source for compatibility
        key = [source_name, line]
        return true if @pragmas[key]&.include?(pragma_sym)

        # Fallback: check without source name (for backward compatibility)
        key_no_source = [nil, line]
        @pragmas[key_no_source]&.include?(pragma_sym)
      end

      # Get the source buffer name and line number for a node
      def node_source_and_line(node)
        return [nil, nil] unless node.respond_to?(:loc) && node.loc

        loc = node.loc
        source_name = nil
        line = nil

        if loc.respond_to?(:expression) && loc.expression
          source_name = loc.expression.source_buffer&.name
          line = loc.expression.line
        elsif loc.respond_to?(:line)
          line = loc.line
          source_name = loc.source_buffer&.name if loc.respond_to?(:source_buffer)
        elsif loc.is_a?(Hash) && loc[:start_line]
          line = loc[:start_line]
        end

        [source_name, line]
      end

      # Handle || with nullish pragma -> ?? or with logical pragma -> || (forces logical)
      def on_or(node)
        if pragma?(node, :nullish) && es2020
          process s(:nullish_or, *node.children)
        elsif pragma?(node, :logical)
          # Force || even when @or option would normally use ??
          process s(:logical_or, *node.children)
        else
          super
        end
      end

      # Handle ||= with nullish pragma -> ??= or with logical pragma -> ||= (forces logical)
      # Note: We check es2020 here because ?? is available then.
      # The converter will decide whether to use ??= (ES2021+) or expand to a = a ?? b
      def on_or_asgn(node)
        if pragma?(node, :nullish) && es2020
          process s(:nullish_asgn, *node.children)
        elsif pragma?(node, :logical)
          # Force ||= even when @or option would normally use ??=
          process s(:logical_asgn, *node.children)
        else
          super
        end
      end

      # Handle def with skip pragma (remove method definition) or noes2015 pragma
      def on_def(node)
        # Skip pragma: remove method definition entirely
        if pragma?(node, :skip)
          return s(:hide)
        end

        if node.children[0].nil? && pragma?(node, :noes2015)
          # Convert anonymous def to deff (forces function syntax)
          # Don't re-process - just update type and process children
          node.updated(:deff, process_all(node.children))
        else
          super
        end
      end

      # Handle defs (class methods like self.foo) with skip pragma
      def on_defs(node)
        if pragma?(node, :skip)
          return s(:hide)
        end
        super
      end

      # Handle alias with skip pragma
      def on_alias(node)
        if pragma?(node, :skip)
          return s(:hide)
        end
        super
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

      # Handle send nodes with type disambiguation and behavior pragmas
      def on_send(node)
        target, method, *args = node.children

        # Skip pragma: remove require/require_relative statements
        if target.nil? && [:require, :require_relative].include?(method)
          if pragma?(node, :skip)
            return s(:hide)
          end
        end

        # Type disambiguation for ambiguous methods
        case method

        # .dup - Array: .slice(), Hash: {...obj}, String: str (no-op in JS)
        when :dup
          if pragma?(node, :array)
            # target.slice() - creates shallow copy of array
            return process s(:send, target, :slice)
          elsif pragma?(node, :hash)
            # {...target}
            return process s(:hash, s(:kwsplat, target))
          elsif pragma?(node, :string)
            # No-op for strings in JS (they're immutable)
            return process target
          end

        # << - Array: push, String: +=
        when :<<
          if pragma?(node, :array) && args.length == 1
            # target.push(arg)
            return process s(:send, target, :push, args.first)
          elsif pragma?(node, :string) && args.length == 1
            # target += arg (returns new string)
            return process s(:op_asgn, target, :+, args.first)
          end

        # .include? - Array: includes(), String: includes(), Hash: 'key' in obj
        when :include?
          if pragma?(node, :hash) && args.length == 1
            # arg in target (uses :in? synthetic type)
            return process s(:in?, args.first, target)
          end
          # Note: array and string both use .includes() which functions filter handles

        # .call - with method pragma, convert proc.call(args) to proc(args)
        when :call
          if pragma?(node, :method) && target
            # Direct invocation using :call type with nil method
            return process node.updated(:call, [target, nil, *args])
          end

        # .class - with proto pragma, use .constructor instead
        when :class
          if pragma?(node, :proto) && target
            return process s(:attr, target, :constructor)
          end
        end

        super
      end

      # Handle self with self pragma -> this
      def on_self(node)
        if pragma?(node, :self_pragma)
          s(:send, nil, :this)
        else
          super
        end
      end

      # Handle hash iteration methods with entries pragma
      # hash.each { |k,v| } -> Object.entries(hash).forEach(([k,v]) => {})
      # hash.map { |k,v| } -> Object.entries(hash).map(([k,v]) => {})
      # hash.select { |k,v| } -> Object.fromEntries(Object.entries(hash).filter(([k,v]) => {}))
      def on_block(node)
        call, args, body = node.children

        if pragma?(node, :noes2015)
          # Transform to use :deff which forces function syntax
          function = node.updated(:deff, [nil, args, body])
          return process s(call.type, *call.children, function)
        end

        if pragma?(node, :entries) && call.type == :send
          target, method = call.children[0], call.children[1]

          if [:each, :each_pair].include?(method) && target
            # Transform: hash.each { |k,v| body }
            # Into: Object.entries(hash).forEach(([k,v]) => body)
            entries_call = s(:send,
              s(:const, nil, :Object), :entries, target)

            # Wrap args in destructuring array pattern if multiple args
            new_args = if args.children.length > 1
              s(:args, s(:mlhs, *args.children))
            else
              args
            end

            # Create new block without location to avoid re-triggering pragma
            return process s(:block,
              s(:send, entries_call, :forEach),
              new_args,
              body
            )

          elsif method == :map && target
            # Transform: hash.map { |k,v| expr }
            # Into: Object.entries(hash).map(([k,v]) => expr)
            entries_call = s(:send,
              s(:const, nil, :Object), :entries, target)

            new_args = if args.children.length > 1
              s(:args, s(:mlhs, *args.children))
            else
              args
            end

            # Create new block without location to avoid re-triggering pragma
            return process s(:block,
              s(:send, entries_call, :map),
              new_args,
              body
            )

          elsif method == :select && target
            # Transform: hash.select { |k,v| expr }
            # Into: Object.fromEntries(Object.entries(hash).filter(([k,v]) => expr))
            entries_call = s(:send,
              s(:const, nil, :Object), :entries, target)

            new_args = if args.children.length > 1
              s(:args, s(:mlhs, *args.children))
            else
              args
            end

            # Create a new block node without location info to avoid re-triggering pragma
            filter_block = s(:block,
              s(:send, entries_call, :filter),
              new_args,
              body
            )

            # Process the inner block first, then wrap with fromEntries
            processed_filter = process filter_block

            return s(:send,
              s(:const, nil, :Object), :fromEntries, processed_filter)
          end
        end

        super
      end
    end

    DEFAULTS.push Pragma
  end
end
