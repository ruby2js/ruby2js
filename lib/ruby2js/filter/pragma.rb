require 'ruby2js'

module Ruby2JS
  module Filter
    module Pragma
      include SEXP

      # Ensure pragma runs before other filters so that pragmas like skip,
      # entries, method, hash, set are processed first.
      #
      # Filter chain: filters.reverse, then include into class chain.
      # Last filter included has highest method resolution priority.
      # So pragma should be first in the array (last after reverse).
      def self.reorder(filters)
        pragma_index = filters.index(Ruby2JS::Filter::Pragma)
        return filters unless pragma_index
        return filters if pragma_index == 0  # Already first

        filters = filters.dup
        filters.delete_at(pragma_index)
        filters.unshift(Ruby2JS::Filter::Pragma)
        filters
      end

      # Mapping from pragma comment text to internal symbol
      PRAGMAS = {
        '??' => :nullish,
        'nullish' => :nullish,
        '||' => :logical,
        'logical' => :logical,       # || stays as || (for boolean false handling)
        'noes2015' => :function,    # legacy alias
        'function' => :function,
        'guard' => :guard,
        # Type disambiguation pragmas
        'array' => :array,
        'hash' => :hash,
        'string' => :string,
        'set' => :set,
        'map' => :map,               # JS Map: []/[]= → get/set, key? → has
        # Behavior pragmas
        'method' => :method,         # proc.call → fn()
        'self' => :self_pragma,      # self → this (avoid conflict with :self)
        'proto' => :proto,           # .class → .constructor
        'entries' => :entries,       # Object.entries for hash iteration
        # Statement control pragmas
        'skip' => :skip,             # skip statement (require, def, defs, alias)
        # Class pragmas
        'extend' => :extend,         # extend existing JS class (monkey patch)
        # Target-specific pragmas (for conditional imports)
        'browser' => :target_browser,
        'capacitor' => :target_capacitor,
        'electron' => :target_electron,
        'tauri' => :target_tauri,
        'electrobun' => :target_electrobun,
        'node' => :target_node,
        'bun' => :target_bun,
        'deno' => :target_deno,
        'cloudflare' => :target_cloudflare,
        'vercel' => :target_vercel,
        'fly' => :target_fly,
        'server' => :target_server   # alias for node/bun/deno/cloudflare/vercel/fly
      }.freeze

      # Map target pragma symbols to their target names (as array for JS compatibility)
      TARGET_PRAGMAS = [
        [:target_browser, 'browser'],
        [:target_capacitor, 'capacitor'],
        [:target_electron, 'electron'],
        [:target_tauri, 'tauri'],
        [:target_electrobun, 'electrobun'],
        [:target_node, 'node'],
        [:target_bun, 'bun'],
        [:target_deno, 'deno'],
        [:target_cloudflare, 'cloudflare'],
        [:target_vercel, 'vercel'],
        [:target_fly, 'fly'],
        [:target_server, 'server']
      ].freeze

      # Server-side targets (for 'server' meta-target)
      SERVER_TARGETS = %w[node bun deno cloudflare vercel fly].freeze

      # Mapping from AST node types to inferred types
      TYPE_INFERENCE = {
        array: :array,
        hash: :hash,
        str: :string,
        dstr: :string,   # interpolated string
        xstr: :string,   # backtick string
        int: :number,
        float: :number,
        regexp: :regexp,
        proc: :proc,     # proc/lambda - callable with []
      }.freeze

      def initialize(*args)
        super
        @pragmas = {}
        @pragma_scanned_count = 0
        @var_types = {}        # Track inferred variable types (method-scoped)
        @var_types_stack = []  # Stack for scope management
        @ivar_types = {}       # Track instance variable types (class-scoped)
        @ivar_types_stack = [] # Stack for class scope management
        @in_initialize = false # Track if we're in an initialize method
        @const_classes = {}    # Track constants assigned class-like values (Struct.new, Class.new)
      end

      def options=(options)
        super
        @pragma_target = options[:target]
      end

      # Infer type from an AST node (literal or constructor call)
      def infer_type(node)
        return nil unless node.respond_to?(:type)

        # Direct literal types
        # Use explicit hash lookup to avoid prototype chain issues in JS.
        # Hash#key? transpiles to `in` which checks prototype chain, so we check
        # if the type is in our known set of keys first.
        if [:array, :hash, :str, :dstr, :xstr, :int, :float, :regexp, :proc].include?(node.type)
          return TYPE_INFERENCE[node.type]
        end

        # Constructor calls: Set.new, Map.new, Array.new, Hash.new, String.new
        if node.type == :send
          receiver, method, *args = node.children
          if method == :new && receiver&.type == :const
            case receiver.children.last
            when :Set then return :set
            when :Map, :$Hash then return :map
            when :Array then return :array
            # Hash.new with args becomes $Hash (Map-like), plain Hash.new stays :hash
            when :Hash then return args.any? ? :map : :hash
            when :String then return :string
            end
          end
        end

        # Hash.new { block } - treat as :map (will become $Hash)
        # proc { } and lambda { } - treat as :proc (callable with [])
        if node.type == :block
          call = node.children.first
          if call.type == :send
            receiver, method = call.children
            if method == :new && receiver&.type == :const && receiver.children.last == :Hash
              return :map
            end
            # proc { } or lambda { } - callable
            if receiver.nil? && [:proc, :lambda].include?(method)
              return :proc
            end
            # group_by { } returns a hash (Object in JS)
            if method == :group_by
              return :hash
            end
          end
        end

        nil
      end

      # Check if node is a T.let(value, Type) call
      # Returns [value_node, type_symbol] if it is, nil otherwise
      def extract_t_let(node)
        return nil unless node&.type == :send
        receiver, method, *args = node.children

        # Check for T.let pattern: receiver is T constant, method is :let, 2 args
        return nil unless method == :let && args.length == 2
        # Check for T constant: [nil, :T] - use element comparison for JS compatibility
        return nil unless receiver&.type == :const &&
          receiver.children.first.nil? && receiver.children.last == :T

        value_node = args[0]
        type_node = args[1]
        type_sym = sorbet_type_to_symbol(type_node)

        type_sym ? [value_node, type_sym] : nil
      end

      # Convert Sorbet type annotation to internal type symbol
      def sorbet_type_to_symbol(node)
        return nil unless node

        # Use explicit returns instead of implicit case expression values for JS compatibility
        if node.type == :const
          # Simple type: Array, Hash, Set, String, Integer, etc.
          case node.children.last
          when :Array then return :array
          when :Hash then return :hash
          when :Set then return :set
          when :Map then return :map
          when :String then return :string
          end
        elsif node.type == :send
          # Generic type: T::Array[X], T::Hash[K,V], T::Set[X]
          receiver, method, *_args = node.children
          if method == :[] && receiver&.type == :const
            # Check for T::Array, T::Hash, T::Set pattern
            parent = receiver.children[0]
            type_name = receiver.children[1]
            # Use element comparison for JS compatibility (array === compares references)
            if parent&.type == :const && parent.children.first.nil? && parent.children.last == :T
              case type_name
              when :Array then return :array
              when :Hash then return :hash
              when :Set then return :set
              end
            end
          end
        end
        nil
      end

      # Track variable types from assignments
      def on_lvasgn(node)
        name, value = node.children
        if value
          # Check for T.let first
          t_let = extract_t_let(value)
          if t_let
            actual_value, type_sym = t_let
            @var_types[name] = type_sym
            # Replace T.let(value, Type) with just value
            return process node.updated(nil, [name, actual_value])
          end

          # Fall back to inference from value
          inferred = infer_type(value)
          @var_types[name] = inferred if inferred
        end
        super
      end

      # Track instance variable types from assignments
      def on_ivasgn(node)
        name, value = node.children
        if value
          # Check for T.let first
          t_let = extract_t_let(value)
          if t_let
            actual_value, type_sym = t_let
            @var_types[name] = type_sym
            # Also store in class-scoped ivar_types if in initialize
            @ivar_types[name] = type_sym if @in_initialize
            # Replace T.let(value, Type) with just value
            return process node.updated(nil, [name, actual_value])
          end

          # Fall back to inference from value
          inferred = infer_type(value)
          if inferred
            @var_types[name] = inferred
            # Also store in class-scoped ivar_types if in initialize
            @ivar_types[name] = inferred if @in_initialize
          end
        end
        super
      end

      # Get the inferred type for a variable reference
      def var_type(node)
        return nil unless node
        case node.type
        when :lvar
          @var_types[node.children.first]
        when :ivar
          # Check method-scoped first, then class-scoped
          name = node.children.first
          @var_types[name] || @ivar_types[name]
        else
          nil
        end
      end

      # Handle array compound assignments that differ between Ruby and JS
      # Transform: arr += [1, 2] => arr.push(...[1, 2])
      # Transform: arr -= [1, 2] => arr = arr.filter(x => ![1, 2].includes(x))
      # Transform: arr &= [1, 2] => arr = arr.filter(x => [1, 2].includes(x))
      # Transform: arr |= [1, 2] => arr = [...new Set([...arr, ...[1, 2]])]
      def on_op_asgn(node)
        target, op, value = node.children

        if [:lvasgn, :ivasgn].include?(target.type)
          var_name = target.children.first
          inferred_type = @var_types[var_name]

          if inferred_type == :array || pragma?(node, :array)
            var_node = target.type == :lvasgn ? s(:lvar, var_name) : s(:ivar, var_name)

            case op
            when :+
              # arr += [1, 2] => arr.push(...[1, 2])
              return process s(:send, var_node, :push, s(:splat, value))

            when :-
              # arr -= [1, 2] => arr = arr.filter(x => ![1, 2].includes(x))
              x_arg = s(:arg, :x)
              x_lvar = s(:lvar, :x)
              includes_call = s(:send, value, :includes, x_lvar)
              negated = s(:send, includes_call, :!)
              filter_block = s(:block,
                s(:send, var_node, :filter),
                s(:args, x_arg),
                negated
              )
              return process s(target.type, var_name, filter_block)

            when :&
              # arr &= [1, 2] => arr = arr.filter(x => [1, 2].includes(x))
              x_arg = s(:arg, :x)
              x_lvar = s(:lvar, :x)
              includes_call = s(:send, value, :includes, x_lvar)
              filter_block = s(:block,
                s(:send, var_node, :filter),
                s(:args, x_arg),
                includes_call
              )
              return process s(target.type, var_name, filter_block)

            when :|
              # arr |= [1, 2] => arr = [...new Set([...arr, ...[1, 2]])]
              spread_both = s(:array, s(:splat, var_node), s(:splat, value))
              set_new = s(:send, s(:const, nil, :Set), :new, spread_both)
              union_result = s(:array, s(:splat, set_new))
              return process s(target.type, var_name, union_result)
            end
          end
        end

        super
      end

      # Scope management: push/pop @var_types at scope boundaries
      def push_var_types_scope
        @var_types_stack.push @var_types
        @var_types = {}
      end

      def pop_var_types_scope
        @var_types = @var_types_stack.pop || {}
      end

      # Scope management for class-scoped instance variable types
      def push_ivar_types_scope
        @ivar_types_stack.push @ivar_types
        @ivar_types = {}
      end

      def pop_ivar_types_scope
        @ivar_types = @ivar_types_stack.pop || {}
      end

      # Scan all comments for pragma patterns and build [source, line] => Set<pragma> map
      # Re-scans when new comments are added (e.g., from require filter merging files)
      # Uses both source buffer name and line number to avoid collisions across files
      def scan_pragmas
        raw_comments = @comments[:_raw] || [] # Pragma: map
        return if raw_comments.length == @pragma_scanned_count

        # Process only new comments (from index @pragma_scanned_count onwards)
        raw_comments[@pragma_scanned_count..].each do |comment|
          text = comment.respond_to?(:text) ? comment.text : comment.to_s

          # Match all "# Pragma: <name>" patterns (case insensitive)
          # Use scan to find ALL pragmas on a line, not just the first
          text.scan(/#\s*Pragma:\s*(\S+)/i).each do |match|
            pragma_name = match[0]
            pragma_sym = PRAGMAS[pragma_name]

            next unless pragma_sym

            # Get the source buffer name and line number of the comment
            source_name = nil
            line = nil

            if comment.respond_to?(:loc) && comment.loc
              loc = comment.loc
              if loc.respond_to?(:expression) && loc.expression
                source_name = loc.expression.source_buffer&.name
                # Use expression.line explicitly for JS compatibility (JS loc doesn't have line getter)
                line = loc.expression.line
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
            # Use Array instead of Set for JS compatibility (JS Set uses .add/.has, not <</.include?)
            key = [source_name, line]
            @pragmas[key] ||= []
            @pragmas[key] << pragma_sym unless @pragmas[key].include?(pragma_sym)
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

      # Check if a node has a target pragma that doesn't match the current target
      # Returns true if the statement should be skipped (target doesn't match)
      def skip_for_target?(node)
        return false unless @pragma_target  # No target set = include everything

        # Check each target pragma to see if it applies to this node
        # TARGET_PRAGMAS is an array of [symbol, name] pairs for JS compatibility
        idx = 0
        target_name = nil

        while idx < TARGET_PRAGMAS.length
          pragma_sym, name = TARGET_PRAGMAS[idx]
          if pragma?(node, pragma_sym)
            target_name = name
            idx = TARGET_PRAGMAS.length  # Exit loop
          end
          idx += 1
        end

        return false unless target_name  # No target pragma = include for all targets

        # Handle 'server' meta-target
        if target_name == 'server'
          !SERVER_TARGETS.include?(@pragma_target)
        else
          @pragma_target != target_name
        end
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

      # Record a diagnostic for an ambiguous method when lint mode is enabled.
      # Only called when type resolution falls through (no pragma, no inferred type).
      # When strict: true, the warning is only emitted if @options[:strict] is set
      # (for methods where the default JS fallthrough is usually correct).
      def record_ambiguous_diagnostic(node, method, valid_types, strict: false)
        return unless @options[:lint]
        return if strict && !@options[:strict]
        diagnostics = @options[:diagnostics]
        return unless diagnostics

        source_name, line = node_source_and_line(node)

        # Skip diagnostics for synthetic nodes (created by filters, not from user source).
        # These have no location info and would produce confusing output.
        return unless line

        column = nil
        if node.respond_to?(:loc) && node.loc
          loc = node.loc
          if loc.respond_to?(:expression) && loc.expression
            column = loc.expression.column
          end
        end

        # Use options[:file] as fallback when AST source buffer name is nil
        # (common with selfhost converter where source buffer names aren't set)
        file = source_name || @options[:file]

        diagnostics.push({
          severity: :warning,
          rule: :ambiguous_method,
          method: method.to_s,
          line: line,
          column: column,
          file: file,
          valid_types: valid_types,
          message: "ambiguous method '#{method}' - receiver type unknown"
        })
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

        # Track if we're in initialize (for class-scoped ivar type tracking)
        method_name = node.children[0]
        was_in_initialize = @in_initialize
        @in_initialize = (method_name == :initialize)

        # New scope for local variable types
        push_var_types_scope
        begin
          if node.children[0].nil? && pragma?(node, :function)
            # Convert anonymous def to deff (forces function syntax)
            # Don't re-process - just update type and process children
            node.updated(:deff, process_all(node.children))
          else
            super
          end
        ensure
          pop_var_types_scope
          @in_initialize = was_in_initialize
        end
      end

      # Handle defs (class methods like self.foo) with skip pragma
      def on_defs(node)
        if pragma?(node, :skip)
          return s(:hide)
        end

        # New scope for local variable types
        push_var_types_scope
        begin
          super
        ensure
          pop_var_types_scope
        end
      end

      # Handle alias with skip pragma
      def on_alias(node)
        if pragma?(node, :skip)
          return s(:hide)
        end
        super
      end

      # Handle if/unless with skip pragma (remove entire block)
      def on_if(node)
        if pragma?(node, :skip)
          return s(:hide)
        end
        super
      end

      # Handle begin blocks with skip pragma
      def on_kwbegin(node)
        if pragma?(node, :skip)
          return s(:hide)
        end
        super
      end

      # Handle while loops with skip pragma
      def on_while(node)
        if pragma?(node, :skip)
          return s(:hide)
        end
        super
      end

      # Handle until loops with skip pragma
      def on_until(node)
        if pragma?(node, :skip)
          return s(:hide)
        end
        super
      end

      # Handle case statements with skip pragma
      def on_case(node)
        if pragma?(node, :skip)
          return s(:hide)
        end
        super
      end

      # Track constant assignments that create class-like values
      # This enables automatic detection of class reopening (e.g., Struct.new + class)
      def on_casgn(node)
        cbase, name, value = node.children

        # Detect: Name = Struct.new(...) or Name = Class.new(...)
        if cbase.nil? && value&.type == :send
          target, method = value.children[0], value.children[1]
          if target&.type == :const &&
             target.children[0].nil? &&
             %i[Struct Class].include?(target.children[1]) &&
             method == :new
            @const_classes[name] = true
          end
        end

        super
      end

      # Handle class definitions with extend pragma (monkey patching)
      # Replaces the ++class syntax with a pragma that works in standard Ruby
      # Also auto-detects class reopening when a class was previously defined
      # via Struct.new or Class.new
      def on_class(node)
        if pragma?(node, :extend)
          # Transform to :class_extend which signals this is extending an existing class
          return process node.updated(:class_extend)
        end

        # Check if this class name was already assigned a class-like value
        # (e.g., Color = Struct.new followed by class Color)
        name_node = node.children.first
        if name_node&.type == :const &&
           name_node.children.first.nil? &&
           @const_classes[name_node.children.last]
          # Treat as class extension (reopening)
          return process node.updated(:class_extend)
        end

        # New scope for local variable types and class-scoped ivar types
        push_var_types_scope
        push_ivar_types_scope
        begin
          super
        ensure
          pop_ivar_types_scope
          pop_var_types_scope
        end
      end

      # Handle module definitions - new scope for variable types
      def on_module(node)
        push_var_types_scope
        begin
          super
        ensure
          pop_var_types_scope
        end
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

        # Skip pragma and target pragmas: remove require/require_relative/import statements
        if target.nil? && [:require, :require_relative, :import].include?(method)
          if pragma?(node, :skip)
            return s(:hide)
          end

          # Target-specific pragma: skip if target doesn't match
          if skip_for_target?(node)
            return s(:hide)
          end

          # require 'sorbet-runtime' → remove (Sorbet is Ruby-only)
          if [:require, :require_relative].include?(method) &&
             args.length == 1 && args.first.type == :str &&
             args.first.children.first == 'sorbet-runtime'
            return s(:hide)
          end
        end

        # Type disambiguation for ambiguous methods
        case method

        # .dup - Array: .slice(), Hash: {...obj}, String: str (no-op in JS)
        when :dup
          # Check pragma first, then fall back to inferred type
          type = if pragma?(node, :array) then :array
                 elsif pragma?(node, :hash) then :hash
                 elsif pragma?(node, :string) then :string
                 else var_type(target)
                 end

          if type == :array
            # target.slice() - creates shallow copy of array
            return process s(:send, target, :slice)
          elsif type == :hash
            # {...target}
            return process s(:hash, s(:kwsplat, target))
          elsif type == :string
            # No-op for strings in JS (they're immutable)
            return process target
          else
            record_ambiguous_diagnostic(node, method, [:array, :hash, :string]) if target
          end

        # << - Array: push, Set: add, String: +=
        when :<<
          # Check pragma first, then fall back to inferred type
          type = if pragma?(node, :array) then :array
                 elsif pragma?(node, :set) then :set
                 elsif pragma?(node, :string) then :string
                 else var_type(target)
                 end

          if type == :array && args.length == 1
            # target.push(arg)
            return process s(:send, target, :push, args.first)
          elsif type == :set && args.length == 1
            # target.add(arg)
            return process s(:send, target, :add, args.first)
          elsif type == :string && args.length == 1
            # target += arg (returns new string)
            return process s(:op_asgn, target, :+, args.first)
          else
            record_ambiguous_diagnostic(node, method, [:array, :set, :string]) if target
          end

        # .include? - Array: includes(), String: includes(), Set: has(), Hash: 'key' in obj
        when :include?
          # Check pragma first, then fall back to inferred type
          type = if pragma?(node, :hash) then :hash
                 elsif pragma?(node, :set) then :set
                 else var_type(target)
                 end

          if type == :hash && args.length == 1
            # arg in target (uses :in? synthetic type)
            return process s(:in?, args.first, target)
          elsif type == :set && args.length == 1
            # target.has(arg) - Set membership check
            return process s(:send, target, :has, args.first)
          else
            record_ambiguous_diagnostic(node, method, [:hash, :set], strict: true) if target
          end
          # Note: array and string both use .includes() which functions filter handles

        # .delete - Set/Map: delete (keep as method), Hash: delete keyword, Array: splice
        when :delete
          # Only apply if this is a real :send node, not from :attr or :call processing
          if node.type == :send
            # Check pragma first, then fall back to inferred type
            type = if pragma?(node, :set) then :set
                   elsif pragma?(node, :map) then :map
                   elsif pragma?(node, :array) then :array
                   else var_type(target)
                   end

            if (type == :set || type == :map) && args.length == 1
              # Transform to (:call (:attr target :delete) nil arg) which produces target.delete(arg)
              # This structure isn't recognized by functions filter, so it won't be converted to delete keyword
              # Don't re-process to avoid infinite loop - just return the transformed node
              return s(:call, s(:attr, process(target), :delete), nil, *args.map { |a| process(a) })
            elsif type == :array && args.length == 1
              # arr.delete(val) → arr.splice(arr.indexOf(val), 1)
              return process s(:send, target, :splice,
                s(:send, target, :indexOf, args.first), s(:int, 1))
            else
              record_ambiguous_diagnostic(node, method, [:set, :map, :array]) if target
            end
          end

        # .clear - Set/Map: clear (keep as method), Array: length = 0, Hash: delete keys
        when :clear
          # Only apply if this is a real :send node, not from :attr or :call processing
          if node.type == :send
            # Check pragma first, then fall back to inferred type
            type = if pragma?(node, :set) then :set
                   elsif pragma?(node, :map) then :map
                   elsif pragma?(node, :hash) then :hash
                   else var_type(target)
                   end

            if (type == :set || type == :map) && args.length == 0
              # Transform to (:call (:attr target :clear) nil) which produces target.clear()
              # This structure isn't recognized by functions filter, so it won't be converted to length = 0
              # Don't re-process to avoid infinite loop - just return the transformed node
              return s(:call, s(:attr, process(target), :clear), nil)
            elsif type == :hash && args.length == 0
              # hash.clear → for (let _key of Object.keys(hash)) delete hash[_key]
              return process s(:for_of, s(:lvasgn, :_key),
                s(:send, s(:const, nil, :Object), :keys, target),
                s(:undef, s(:send, target, :[], s(:lvar, :_key))))
            else
              record_ambiguous_diagnostic(node, method, [:set, :map, :hash]) if target
            end
          end

        # .merge - Set: iterate and add, Hash: Object.assign / spread
        when :merge
          type = if pragma?(node, :set) then :set
                 else var_type(target)
                 end

          if type == :set && args.length == 1
            # target.merge(items) → for (let item of items) target.add(item)
            item_var = :_item
            return process s(:for_of, s(:lvasgn, item_var),
              args.first,
              s(:send, target, :add, s(:lvar, item_var)))
          else
            record_ambiguous_diagnostic(node, method, [:set], strict: true) if target
          end

        # [] - Map: get, Proc: call, Hash/Array: bracket access
        when :[]
          # Check pragma first, then fall back to inferred type
          type = if pragma?(node, :map) then :map
                 else var_type(target)
                 end

          if type == :map && args.length == 1
            # target.get(key)
            return process s(:send, target, :get, args.first)
          elsif type == :proc
            # proc[args] -> proc(args) - direct function call
            return process node.updated(:call, [target, nil, *args])
          else
            record_ambiguous_diagnostic(node, method, [:map, :proc], strict: true) if target
          end

        # []= - Map: set (keep as method call), Hash/Array: bracket assignment
        when :[]=
          # Check pragma first, then fall back to inferred type
          type = if pragma?(node, :map) then :map
                 else var_type(target)
                 end

          if type == :map && args.length == 2
            # target.set(key, value)
            return process s(:send, target, :set, *args)
          else
            record_ambiguous_diagnostic(node, method, [:map], strict: true) if target
          end

        # .key? - Map: has, Hash: 'key' in obj
        when :key?
          # Check pragma first, then fall back to inferred type
          type = if pragma?(node, :map) then :map
                 else var_type(target)
                 end

          if type == :map && args.length == 1
            # target.has(key)
            return process s(:send, target, :has, args.first)
          else
            record_ambiguous_diagnostic(node, method, [:map], strict: true) if target
          end

        # .any? - Hash: Object.keys(hash).length > 0 (without block)
        when :any?
          # Check pragma first, then fall back to inferred type
          type = if pragma?(node, :hash) then :hash
                 else var_type(target)
                 end

          if type == :hash && args.empty?
            # Object.keys(target).length > 0
            return process s(:send,
              s(:attr, s(:send, s(:const, nil, :Object), :keys, target), :length),
              :>, s(:int, 0))
          else
            record_ambiguous_diagnostic(node, method, [:hash], strict: true) if target
          end

        # .empty? - Hash: Object.keys(hash).length === 0, Set/Map: size === 0
        when :empty?
          # Check pragma first, then fall back to inferred type
          type = if pragma?(node, :hash) then :hash
                 elsif pragma?(node, :set) then :set
                 elsif pragma?(node, :map) then :map
                 else var_type(target)
                 end

          if type == :hash && args.empty?
            # Object.keys(target).length === 0
            return process s(:send,
              s(:attr, s(:send, s(:const, nil, :Object), :keys, target), :length),
              :===, s(:int, 0))
          elsif (type == :set || type == :map) && args.empty?
            # target.size === 0 (JS Sets/Maps use .size not .length)
            return process s(:send, s(:attr, target, :size), :==, s(:int, 0))
          else
            record_ambiguous_diagnostic(node, method, [:hash, :set, :map], strict: true) if target
          end
          # Note: array and string use .length which functions filter handles

        # Array binary operators that differ between Ruby and JS
        # a + b → [...a, ...b]  (concat - JS + does string concat on arrays)
        when :+
          type = if pragma?(node, :array) then :array
                 else var_type(target)
                 end

          if type == :array && target && args.length == 1
            # [...a, ...b]
            return process s(:array, s(:splat, target), s(:splat, args.first))
          elsif target && args.length == 1 &&
              ![:int, :float, :str].include?(target.type) &&
              ![:int, :float, :str].include?(args.first.type)
            record_ambiguous_diagnostic(node, method, [:array])
          end

        # a - b → a.filter(x => !b.includes(x))  (difference - JS - gives NaN)
        when :-
          type = if pragma?(node, :array) then :array
                 else var_type(target)
                 end

          if type == :array && target && args.length == 1
            # Generate: target.filter(x => !args.first.includes(x))
            x_arg = s(:arg, :x)
            x_lvar = s(:lvar, :x)
            includes_call = s(:send, args.first, :includes, x_lvar)
            negated = s(:send, includes_call, :!)
            return process s(:block,
              s(:send, target, :filter),
              s(:args, x_arg),
              negated
            )
          elsif target && args.length == 1 &&
              ![:int, :float, :str].include?(target.type) &&
              ![:int, :float, :str].include?(args.first.type)
            record_ambiguous_diagnostic(node, method, [:array])
          end

        # a & b → a.filter(x => b.includes(x))  (intersection - JS & is bitwise)
        when :&
          type = if pragma?(node, :array) then :array
                 else var_type(target)
                 end

          if type == :array && target && args.length == 1
            # Generate: target.filter(x => args.first.includes(x))
            x_arg = s(:arg, :x)
            x_lvar = s(:lvar, :x)
            includes_call = s(:send, args.first, :includes, x_lvar)
            return process s(:block,
              s(:send, target, :filter),
              s(:args, x_arg),
              includes_call
            )
          else
            record_ambiguous_diagnostic(node, method, [:array]) if target
          end

        # a | b → [...new Set([...a, ...b])]  (union - JS | is bitwise)
        when :|
          type = if pragma?(node, :array) then :array
                 else var_type(target)
                 end

          if type == :array && target && args.length == 1
            # Generate: [...new Set([...a, ...b])]
            spread_both = s(:array, s(:splat, target), s(:splat, args.first))
            set_new = s(:send, s(:const, nil, :Set), :new, spread_both)
            return process s(:array, s(:splat, set_new))
          else
            record_ambiguous_diagnostic(node, method, [:array]) if target
          end

        # .replace - String: reassignment (JS strings are immutable)
        when :replace
          type = if pragma?(node, :string) then :string
                 else var_type(target)
                 end

          if type == :string && args.length == 1
            # str.replace(other) → str = other (reassignment)
            if target&.type == :lvar
              return process s(:lvasgn, target.children.first, args.first)
            elsif target&.type == :ivar
              return process s(:ivasgn, target.children.first, args.first)
            end
          else
            record_ambiguous_diagnostic(node, method, [:string], strict: true) if target
          end

        # .first - Hash: Object.entries(hash)[0]
        when :first
          type = if pragma?(node, :hash) then :hash
                 else var_type(target)
                 end

          if type == :hash && args.empty?
            # hash.first → Object.entries(hash)[0]
            return process s(:send,
              s(:send, s(:const, nil, :Object), :entries, target),
              :[], s(:int, 0))
          else
            record_ambiguous_diagnostic(node, method, [:hash], strict: true) if target
          end

        # .to_h - Hash: no-op identity
        when :to_h
          type = if pragma?(node, :hash) then :hash
                 else var_type(target)
                 end

          if type == :hash && args.empty?
            return process target
          else
            record_ambiguous_diagnostic(node, method, [:hash], strict: true) if target
          end

        # .compact - Hash: Object.fromEntries(Object.entries(hash).filter(([k,v]) => v != null))
        when :compact
          type = if pragma?(node, :hash) then :hash
                 else var_type(target)
                 end

          if type == :hash && args.empty?
            entries_call = s(:send, s(:const, nil, :Object), :entries, target)
            # Build: .filter(([k,v]) => v != null)
            filter_block = s(:block,
              s(:send, entries_call, :filter),
              s(:args, s(:mlhs, s(:arg, :_k), s(:arg, :_v))),
              s(:send, s(:lvar, :_v), :!=, s(:nil)))
            return process s(:send,
              s(:const, nil, :Object), :fromEntries, filter_block)
          else
            record_ambiguous_diagnostic(node, method, [:hash], strict: true) if target
          end

        # .flatten - Hash: no-op (not meaningful for hashes, return entries)
        when :flatten
          type = if pragma?(node, :hash) then :hash
                 else var_type(target)
                 end

          if type == :hash && args.empty?
            # hash.flatten → Object.entries(hash).flat(Infinity)
            return process s(:send,
              s(:send, s(:const, nil, :Object), :entries, target),
              :flat, s(:lvar, :Infinity))
          else
            record_ambiguous_diagnostic(node, method, [:hash], strict: true) if target
          end

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
      #
      # Also handles shadowargs - block-local variables that shadow outer scope
      # These create JS-scoped let declarations, so we preserve outer types
      # Check if a block body contains break or next statements (which are
      # invalid inside forEach callbacks but valid inside for...of loops)
      def contains_break_or_next?(node)
        return false unless node.respond_to?(:type)
        return true if node.type == :break || node.type == :next
        # Don't descend into nested blocks/lambdas - they have their own scope
        return false if [:block, :lambda].include?(node.type)
        node.children.any? { |c| contains_break_or_next?(c) }
      end

      def on_block(node)
        call, args, body = node.children

        # Check for shadowargs (block-local variables that shadow outer scope)
        # Note: args can be nil when using Ruby 3.4's `it` implicit block parameter
        shadowargs = args&.children&.select { |arg| arg.type == :shadowarg } || []
        saved_types = {}

        if shadowargs.any?
          # Save and clear types for shadowed variables
          shadowargs.each do |arg|
            name = arg.children.first
            saved_types[name] = @var_types[name] if @var_types.key?(name)
            @var_types.delete(name)
          end
        end

        begin
          if pragma?(node, :function)
            # Transform to use :deff which forces function syntax
            function = node.updated(:deff, [nil, args, body])
            return process s(call.type, *call.children, function)
          end

          if call.type == :send &&
            (pragma?(node, :entries) ||
             var_type(call.children[0]) == :hash ||
             infer_type(call.children[0]) == :hash)
          target, method = call.children[0], call.children[1]

          if [:each, :each_pair].include?(method) && target
            # Transform: hash.each { |k,v| body }
            entries_call = s(:send,
              s(:const, nil, :Object), :entries, target)

            # Wrap args in destructuring array pattern if multiple args
            new_args = if args.children.length > 1
              s(:args, s(:mlhs, *args.children))
            else
              args
            end

            if contains_break_or_next?(body)
              # Use for...of when body contains break/next (invalid in forEach)
              # Into: for (let [k,v] of Object.entries(hash)) { body }
              lvasgn = if args.children.length > 1
                s(:mlhs, *args.children.map { |a| s(:lvasgn, a.children.first) })
              elsif args.children.length == 1
                s(:lvasgn, args.children.first.children.first)
              else
                s(:lvasgn, :_)
              end
              return process node.updated(:for_of, [lvasgn, entries_call, body])
            end

            # Into: Object.entries(hash).forEach(([k,v]) => body)
            return process s(:block,
              s(:send, entries_call, :forEach),
              new_args,
              body
            )

          elsif [:map, :collect].include?(method) && target
            # Transform: hash.map { |k,v| expr } or hash.collect { |k,v| expr }
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

        # Handle hash reduce/inject, flat_map, each_with_index
        # Wrap receiver in Object.entries() and destructure block args
        if call.type == :send
          target, method = call.children[0], call.children[1]
          if target && [:reduce, :inject, :flat_map, :each_with_index].include?(method)
            type = if pragma?(node, :entries) || pragma?(node, :hash) then :hash
                   else var_type(target) || infer_type(target)
                   end

            if type == :hash
              entries_call = s(:send, s(:const, nil, :Object), :entries, target)

              if [:reduce, :inject].include?(method)
                # hash.reduce(init) { |acc, (k,v)| ... } → Object.entries(hash).reduce(...)
                # Use s() to create new node without location to avoid re-triggering pragma
                return process s(:block,
                  s(:send, entries_call, :reduce, *call.children[2..]),
                  args,
                  body
                )

              elsif method == :flat_map
                # hash.flat_map { |k,v| ... } → Object.entries(hash).flatMap(([k,v]) => ...)
                new_args = if args&.children&.length.to_i > 1
                  s(:args, s(:mlhs, *args.children))
                else
                  args
                end
                return process s(:block,
                  s(:send, entries_call, :flat_map),
                  new_args,
                  body
                )

              elsif method == :each_with_index
                # hash.each_with_index { |(k,v), i| ... } → Object.entries(hash).forEach(([k,v], i) => ...)
                return process s(:block,
                  s(:send, entries_call, :each_with_index),
                  args,
                  body
                )
              end
            end
          end
        end

        # Handle Set.select - JS Sets don't have filter(), so convert to array first
        # set.select { |x| expr } → [...set].filter(x => expr)
        if call.type == :send
          target, method = call.children[0], call.children[1]
          if method == :select && target
            type = pragma?(node, :set) ? :set : var_type(target)
            if type == :set
              # Wrap set in array spread: [...set]
              spread_array = s(:array, s(:splat, target))
              # Create filter block on the spread array
              return process node.updated(nil, [
                s(:send, spread_array, :filter),
                args,
                body
              ])
            end
          end
        end

        # Lint: warn about potential hash iteration when block has 2+ args
        # and receiver type is unknown (suggesting user may intend hash iteration)
        if @options[:lint] && call.type == :send
          lint_target = call.children[0]
          lint_method = call.children[1]
          if lint_target && args&.children&.length.to_i > 1 &&
             [:each, :each_pair, :map, :collect, :select, :flat_map, :each_with_index].include?(lint_method)
            lint_type = var_type(lint_target) || infer_type(lint_target)
            unless lint_type
              record_ambiguous_diagnostic(node, lint_method, [:hash], strict: true)
            end
          end
        end

        super
        ensure
          # Restore types for shadowed variables
          if shadowargs.any?
            shadowargs.each do |arg|
              name = arg.children.first
              if saved_types.key?(name)
                @var_types[name] = saved_types[name]
              else
                @var_types.delete(name)
              end
            end
          end
        end
      end
    end

    DEFAULTS.push Pragma
  end
end
