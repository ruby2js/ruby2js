# frozen_string_literal: true

require 'ruby2js'
require 'ruby2js/inflector'

module Ruby2JS
  module Spa
    # Resolves model dependencies by parsing model files and walking the AST
    # to find association declarations (has_many, belongs_to, has_one).
    #
    # Uses Ruby2JS.parse which returns consistent Parser-compatible AST
    # regardless of which parser (Prism or parser gem) is active.
    #
    # Example:
    #   resolver = ModelResolver.new('/path/to/rails/app')
    #   resolver.resolve([:Article, :Comment])
    #   # => { Article: { associations: [...], file: '...' }, Comment: { ... } }
    #
    class ModelResolver
      attr_reader :rails_root, :models_path, :resolved_models

      def initialize(rails_root)
        @rails_root = rails_root.to_s
        @models_path = File.join(@rails_root, 'app', 'models')
        @resolved_models = {}
      end

      # Resolve all dependencies starting from the given model names.
      # Returns a hash of model_name => model_info
      def resolve(model_names)
        @resolved_models = {}
        queue = model_names.map(&:to_sym)

        while (model_name = queue.shift)
          next if @resolved_models.key?(model_name)

          model_info = parse_model(model_name)
          next unless model_info

          @resolved_models[model_name] = model_info

          # Add associated models to the queue
          model_info[:associations].each do |assoc|
            class_name = assoc[:class_name].to_sym
            queue << class_name unless @resolved_models.key?(class_name)
          end
        end

        @resolved_models
      end

      # Parse a single model file and extract metadata
      def parse_model(model_name)
        file_path = model_file_path(model_name)
        return nil unless File.exist?(file_path)

        source = File.read(file_path)
        ast, _ = Ruby2JS.parse(source)
        return nil unless ast

        extract_model_info(model_name, file_path, ast)
      end

      private

      def model_file_path(model_name)
        # Convert CamelCase to snake_case
        snake_case = model_name.to_s.gsub(/([A-Z])/, '_\1').downcase.sub(/^_/, '')
        File.join(@models_path, "#{snake_case}.rb")
      end

      def extract_model_info(model_name, file_path, ast)
        associations = []
        validations = []
        callbacks = []
        scopes = []

        # Walk the AST to find DSL calls
        walk_ast(ast) do |node|
          next unless node.type == :send && node.children[0].nil?

          method_name = node.children[1]
          args = node.children[2..]

          case method_name
          when :has_many, :has_one, :belongs_to
            assoc = extract_association(method_name, args)
            associations << assoc if assoc
          when :validates
            validations << extract_validation(args)
          when :scope
            scopes << extract_scope(args)
          when :before_save, :after_save, :before_create, :after_create,
               :before_update, :after_update, :before_destroy, :after_destroy,
               :before_validation, :after_validation
            callbacks << { type: method_name, methods: extract_callback_methods(args) }
          end
        end

        {
          name: model_name,
          file: file_path,
          associations: associations,
          validations: validations,
          callbacks: callbacks,
          scopes: scopes
        }
      end

      def walk_ast(node, &block)
        return unless node.respond_to?(:type)

        yield node

        node.children.each { |child| walk_ast(child, &block) }
      end

      def extract_association(type, args)
        return nil if args.empty?
        return nil unless args.first.type == :sym

        name = args.first.children[0]
        options = extract_hash_options(args[1])

        # Determine the associated class name
        class_name = options[:class_name] || infer_class_name(type, name)

        {
          type: type,
          name: name,
          class_name: class_name,
          foreign_key: options[:foreign_key],
          dependent: options[:dependent],
          optional: options[:optional]
        }
      end

      def infer_class_name(type, name)
        case type
        when :has_many
          # has_many :comments -> Comment
          Inflector.singularize(name.to_s).capitalize
        when :has_one, :belongs_to
          # belongs_to :article -> Article
          name.to_s.capitalize
        end
      end

      def extract_validation(args)
        attributes = []
        rules = {}

        args.each do |arg|
          case arg.type
          when :sym
            attributes << arg.children[0]
          when :hash
            rules.merge!(extract_hash_options(arg))
          end
        end

        { attributes: attributes, rules: rules }
      end

      def extract_scope(args)
        return nil if args.size < 2
        return nil unless args[0].type == :sym

        { name: args[0].children[0], body: args[1] }
      end

      def extract_callback_methods(args)
        args.select { |arg| arg.type == :sym }
            .map { |arg| arg.children[0] }
      end

      def extract_hash_options(node)
        return {} unless node&.type == :hash

        options = {}
        node.children.each do |pair|
          next unless pair.type == :pair

          key_node = pair.children[0]
          value_node = pair.children[1]

          next unless key_node.type == :sym

          key = key_node.children[0]
          value = extract_value(value_node)
          options[key] = value
        end

        options
      end

      def extract_value(node)
        case node.type
        when :sym then node.children[0]
        when :str then node.children[0]
        when :int then node.children[0]
        when :true then true
        when :false then false
        when :nil then nil
        when :hash then extract_hash_options(node)
        else node
        end
      end
    end
  end
end
