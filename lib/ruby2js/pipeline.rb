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
      filters = @filters.dup
      filters.each do |filter|
        filters = filter.reorder(filters) if filter.respond_to?(:reorder)
      end

      # Build filter chain using mixins
      # Each filter module is included into an anonymous class
      filter_class = Filter::Processor
      filters.reverse.each do |mod|
        filter_class = Class.new(filter_class) { include mod }
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
      return unless raw_comments && !raw_comments.empty?

      begin
        # Use Parser gem's associate if available (Ruby), otherwise our own (JS selfhost)
        new_comments = if defined?(Parser) && defined?(Parser::Source::Comment)
          Parser::Source::Comment.associate(@ast, raw_comments)
        elsif defined?(Ruby2JS) && Ruby2JS.respond_to?(:associate_comments)
          Ruby2JS.associate_comments(@ast, raw_comments)
        else
          # Selfhost: use global associateComments function
          associateComments(@ast, raw_comments)
        end

        if new_comments && !new_comments.empty?
          @comments.clear
          @comments.merge!(new_comments)
          @comments[:_raw] = raw_comments
        end
      rescue NoMethodError
        # Synthetic nodes without location info cause associate to fail
        # Keep original comments hash
      end
    end

    def handle_prepend_list
      return unless @filter_instance
      return if @filter_instance.prepend_list.empty?

      prepend = @filter_instance.prepend_list.sort_by { |node| node.type == :import ? 0 : 1 }

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
      @comments[@ast] = []
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
