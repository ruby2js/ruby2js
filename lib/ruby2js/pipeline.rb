# Transpilable orchestration for Ruby2JS conversion
#
# This class handles:
# - Filter chain building using Class.new { include mod }
# - Filter application
# - Comment re-association after filtering
# - Prepend list handling
# - Converter setup and execution
#
# Ruby-specific concerns (Proc handling, config files, binding/ivars)
# remain in ruby2js.rb which delegates to this class.

module Ruby2JS
  # Helper for filter composition: wrap methods to inject correct _parent for super calls.
  # Ruby's super is dynamic, but JS super is lexically bound. When methods are copied
  # via Object.defineProperties, we need each method to have its own parent reference.
  # This function only runs in JS context (guarded by defined?(globalThis) at call site).
  # Uses Function.new to create regular functions with dynamic `this` binding.
  def self.wrapMethodsWithParent(proto, parent_proto)
    Object.getOwnPropertyNames(proto).each do |key|
      next if key == 'constructor'
      desc = Object.getOwnPropertyDescriptor(proto, key)
      next unless typeof(desc.value) == 'function'

      original_fn = desc.value
      desc.value = Function.new { |*args|
        old_parent = self._parent
        self._parent = parent_proto
        begin
          return original_fn.apply(self, args)
        ensure
          self._parent = old_parent
        end
      }
      Object.defineProperty(proto, key, desc)
    end
  end

  class Pipeline
    attr_reader :ast, :comments, :options
    attr_accessor :namespace

    def initialize(ast, comments, filters: [], options: {})
      @original_ast = ast
      @ast = ast
      @comments = comments
      @filters = filters
      @options = options
      @namespace = options[:namespace] || Namespace.new
      @filter_instance = nil
    end

    def run
      apply_filters if @filters && !@filters.empty?
      # Always reassociate comments (for trailing/orphan comment handling)
      # even when no filters are applied
      reassociate_comments unless @filters && !@filters.empty?
      create_converter
      configure_converter
      execute_converter
      @converter
    end

    private

    def apply_filters
      filter_options = @options.merge({ filters: @filters })

      # Allow filters to reorder themselves
      filters = [*@filters]
      filters.each do |filter|
        filters = filter.reorder(filters) if filter.respond_to?(:reorder)
      end

      # Build filter chain using mixins
      # Each filter module is included into an anonymous class.
      # In Ruby: Class.new(parent) { include mod }
      # In JS: Use Object.defineProperties to properly copy getters without invoking them
      # (Object.assign would invoke getters, which fails for methods like scan_pragmas
      # that access instance variables before the instance is created)
      filter_class = Filter::Processor
      filters.reverse.each do |mod|
        parent_class = filter_class
        filter_class = Class.new(filter_class) { include mod }

        # For JS selfhost: wrap methods to inject correct _parent for dynamic super lookup
        # Ruby's super is dynamic, but JS super is lexically bound to original class.
        # In Ruby: globalThis is not defined, so this is a no-op
        if defined?(globalThis)
          Ruby2JS.wrapMethodsWithParent(filter_class.prototype, parent_class.prototype)
        end
      end
      @filter_instance = filter_class.new(@comments)

      # Call _filter_init if it exists (for selfhost filters where initialize → _filter_init)
      # In Ruby, initialize is called by new, but in JS selfhost the filter chain uses
      # prototype copying which doesn't invoke constructors. _filter_init provides
      # the initialization logic with proper _parent chaining.
      if defined?(globalThis) && @filter_instance.respond_to?(:_filter_init)
        @filter_instance._filter_init(@comments)
      end

      # Configure filter
      @filter_instance.options = filter_options
      @filter_instance.namespace = @namespace

      if @options[:disable_autoimports]
        @filter_instance.disable_autoimports = true
      end
      if @options[:disable_autoexports]
        @filter_instance.disable_autoexports = true
      end

      # Apply filters to AST
      @ast = @filter_instance.process(@ast)

      # Re-associate comments with filtered AST
      reassociate_comments

      # Handle prepend list (imports, polyfills)
      handle_prepend_list
    end

    def reassociate_comments
      # Access _raw: Ruby Hash uses [], JS Map uses .get() via pragma
      raw_comments = @comments[:_raw] # Pragma: map
      return unless raw_comments && raw_comments.length > 0

      # Comment association strategy:
      # 1. Collect all nodes with location from filtered AST
      # 2. Sort by source position
      # 3. For each comment:
      #    - If on same line as a node that ends before it: trailing comment
      #    - Else if there's a next node: associate with next node
      #    - Else: orphan comment (output at end)

      # Collect nodes with location info
      nodes = []
      collect_located_nodes(@ast, nodes)

      # Sort by start position (use assignment for JS compatibility)
      nodes = nodes.sort_by { |n| node_start_pos(n) }

      # Build new comments map: associate each comment with next node
      # Clear existing entries (but preserve _raw)
      # Note: Can't use # Pragma: map for clear because we need to preserve _raw
      if @comments.respond_to?(:set)
        # JS Map: save _raw, clear, restore
        saved_raw = @comments[:_raw] # Pragma: map
        @comments.clear() # Pragma: map
        @comments[:_raw] = saved_raw if saved_raw # Pragma: map
      else
        # Ruby Hash
        @comments.clear
      end

      trailing_comments = []
      orphan_comments = []

      raw_comments.each do |comment|
        comment_line = comment_line_number(comment)
        comment_end = comment_end_pos(comment)
        next unless comment_end && comment_line

        # Check if this is a trailing comment (same line as a node that ends before it)
        # Find the node with the largest end_pos (outermost/statement-level) to avoid
        # matching child nodes like `self` instead of the full `self['id'] = @_id`
        comment_start = comment_start_pos(comment)
        comment_source = comment_source_name(comment)
        same_line_node = nil
        best_end = -1
        nodes.each do |n|
          node_line = node_line_number(n)
          node_end = node_end_pos(n)
          next unless node_line && node_end && node_line == comment_line
          next unless comment_start.nil? || node_end <= comment_start
          # Ensure comment and node are from the same source file (when multi-file)
          node_source = node_source_name(n)
          next if comment_source && node_source && comment_source != node_source
          if node_end > best_end
            best_end = node_end
            same_line_node = n
          end
        end

        if same_line_node
          # Trailing comment - store separately with node reference
          trailing_comments.push([same_line_node, comment])
        else
          # Find first node that starts at or after comment ends
          target = nodes.find { |n| node_start_pos(n) >= comment_end }

          if target
            # Add comment to target's list
            if @comments.respond_to?(:set)
              existing = @comments[target] || [] # Pragma: map
              existing.push(comment)
              @comments[target] = existing # Pragma: map
            else
              @comments[target] ||= []
              @comments[target].push(comment)
            end
          else
            # No target - orphan comment
            orphan_comments.push(comment)
          end
        end
      end

      # Store trailing and orphan comments under special keys
      if trailing_comments.length > 0
        if @comments.respond_to?(:set)
          @comments[:_trailing] = trailing_comments # Pragma: map
        else
          @comments[:_trailing] = trailing_comments
        end
      end

      if orphan_comments.length > 0
        if @comments.respond_to?(:set)
          @comments[:_orphan] = orphan_comments # Pragma: map
        else
          @comments[:_orphan] = orphan_comments
        end
      end

      # Re-add _raw
      @comments[:_raw] = raw_comments # Pragma: map
    end

    # Recursively collect all nodes with location info
    def collect_located_nodes(node, result)
      return unless node.respond_to?(:type) && node.respond_to?(:children)

      # Add this node if it has location info (skip :begin nodes like Parser does)
      # Note: Use explicit nil check because start_pos can be 0 (falsy in JS)
      if node.type != :begin && !node_start_pos(node).nil?
        result.push(node)
      end

      # Recurse into children
      node.children.each do |child|
        collect_located_nodes(child, result) if child.respond_to?(:type)
      end
    end

    # Get start position from a node's location
    def node_start_pos(node)
      return nil unless node.respond_to?(:loc) && node.loc
      if node.loc.respond_to?(:expression) && node.loc.expression
        node.loc.expression.begin_pos
      elsif node.loc.respond_to?(:[]) && node.loc[:expression]
        node.loc[:expression].begin_pos
      else
        nil
      end
    end

    # Get end position from a node's location
    def node_end_pos(node)
      return nil unless node.respond_to?(:loc) && node.loc
      if node.loc.respond_to?(:expression) && node.loc.expression
        node.loc.expression.end_pos
      elsif node.loc.respond_to?(:[]) && node.loc[:expression]
        node.loc[:expression].end_pos
      else
        nil
      end
    end

    # Get line number from a node's location
    def node_line_number(node)
      return nil unless node.respond_to?(:loc) && node.loc
      if node.loc.respond_to?(:expression) && node.loc.expression
        node.loc.expression.line
      elsif node.loc.respond_to?(:[]) && node.loc[:start_line]
        node.loc[:start_line]
      else
        nil
      end
    end

    # Get end position from a comment's location
    def comment_end_pos(comment)
      if comment.loc&.respond_to?(:expression) && comment.loc.expression
        comment.loc.expression.end_pos
      elsif comment.respond_to?(:location) && comment.location
        comment.location.end_offset
      else
        nil
      end
    end

    # Get start position from a comment's location
    def comment_start_pos(comment)
      if comment.loc&.respond_to?(:expression) && comment.loc.expression
        comment.loc.expression.begin_pos
      elsif comment.respond_to?(:location) && comment.location
        comment.location.start_offset
      else
        nil
      end
    end

    # Get source buffer name from a comment's location
    def comment_source_name(comment)
      if comment.loc&.respond_to?(:expression) && comment.loc.expression
        comment.loc.expression.source_buffer&.name
      elsif comment.respond_to?(:location) && comment.location&.respond_to?(:source_buffer)
        comment.location.source_buffer&.name
      else
        nil
      end
    end

    # Get source buffer name from a node's location
    def node_source_name(node)
      return nil unless node.respond_to?(:loc) && node.loc
      if node.loc.respond_to?(:expression) && node.loc.expression
        node.loc.expression.source_buffer&.name
      elsif node.loc.respond_to?(:source_buffer)
        node.loc.source_buffer&.name
      else
        nil
      end
    end

    # Get line number from a comment's location
    def comment_line_number(comment)
      if comment.loc&.respond_to?(:expression) && comment.loc.expression
        comment.loc.expression.line
      elsif comment.respond_to?(:location) && comment.location
        comment.location.start_line
      else
        nil
      end
    end

    def handle_prepend_list
      return unless @filter_instance
      return if @filter_instance.prepend_list.empty?

      # Deduplicate imports (same node object added multiple times, e.g., from require filter)
      prepend = @filter_instance.prepend_list.uniq
      prepend = prepend.sort_by { |node| node.type == :import ? 0 : 1 }

      if @filter_instance.disable_autoimports
        prepend = prepend.reject { |node| node.type == :import }
      end

      return if prepend.empty?

      # Wrap AST with prepended nodes
      # Use Parser::AST::Node in Ruby, Ruby2JS::Node in JS selfhost
      @ast = if defined?(Parser) && defined?(Parser::AST::Node)
        Parser::AST::Node.new(:begin, [*prepend, @ast])
      else
        Ruby2JS::Node.new(:begin, [*prepend, @ast])
      end

      # Register empty comments for the new :begin node to prevent
      # it from inheriting comments from its first child
      # Use Map.set() for selfhost JS, bracket notation for Ruby
      if @comments.respond_to?(:set)
        @comments.set(@ast, [])
      else
        @comments[@ast] = []
      end
    end

    def create_converter
      @converter = Converter.new(@ast, @comments)
    end

    def configure_converter
      @converter.namespace = @namespace

      # ES level and output options
      @converter.eslevel = @options[:eslevel] || 2020
      @converter.strict = @options[:strict] || false
      @converter.comparison = @options[:comparison] || :equality
      @converter.or = @options[:or] || :auto
      @converter.truthy = @options[:truthy] || :js
      @converter.nullish_to_s = @options[:nullish_to_s] || false
      @converter.module_type = @options[:module] || :esm
      @converter.underscored_private = (@options[:eslevel].to_i < 2022) || @options[:underscored_private]

      # Binding and ivars (needed before convert for variable substitution)
      @converter.binding = @options[:binding]
      @converter.ivars = @options[:ivars]

      # Width for output formatting
      @converter.width = @options[:width] if @options[:width]

      # Enable vertical whitespace if source had newlines
      if @options[:source] && @options[:source].include?("\n")
        @converter.enable_vertical_whitespace
      end
    end

    def execute_converter
      @converter.convert
    end
  end
end
