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
      raw_comments = @comments[:_raw]
      return if raw_comments.nil? || raw_comments.length == 0

      begin
        # Use Parser gem's associate if available (Ruby), otherwise our own (JS selfhost)
        # Note: Ruby uses defined? for safe constant checking; JS needs optional chaining
        new_comments = nil
        unless defined?(RUBY2JS_SELFHOST) # Pragma: skip
          if defined?(Parser) && defined?(Parser::Source::Comment)
            new_comments = Parser::Source::Comment.associate(@ast, raw_comments)
          elsif defined?(Ruby2JS) && Ruby2JS.respond_to?(:associate_comments)
            new_comments = Ruby2JS.associate_comments(@ast, raw_comments)
          else
            new_comments = associateComments(@ast, raw_comments)
          end
        end

        # JS selfhost: use associateComments directly
        new_comments = associateComments(@ast, raw_comments) # Pragma: only-js

        # Ruby: use Hash methods
        unless defined?(RUBY2JS_SELFHOST) # Pragma: skip
          if new_comments && !new_comments.empty?
            @comments.clear
            @comments.merge!(new_comments)
            @comments[:_raw] = raw_comments
          end
        end

        # JS selfhost: use Map methods (size not empty, set())
        # Note: Clear old entries by setting to empty (delete gets transformed by functions
        # filter to `delete obj[key]` which doesn't work for Maps - they need .delete() method)
        if new_comments && new_comments.size != 0 # Pragma: only-js
          @comments.forEach { |_, key| @comments.set(key, []) unless key == "_raw" } # Pragma: only-js
          new_comments.forEach { |value, key| @comments.set(key, value) } # Pragma: only-js
          @comments.set("_raw", raw_comments) # Pragma: only-js
        end # Pragma: only-js
      rescue NoMethodError # Pragma: skip
        # Synthetic nodes without location info cause associate to fail
        # Keep original comments hash
      end # Pragma: skip
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
