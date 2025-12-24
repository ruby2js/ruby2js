# frozen_string_literal: true

require 'ruby2js'

module Ruby2JS
  module Spa
    # Parses db/schema.rb (or config/schema.rb) and extracts table structure
    # for generating Dexie.js schema.
    #
    # Dexie schema format: 'tableName': '++id, indexed_field, another_field'
    #   ++id = auto-incrementing primary key
    #   field = indexed field
    #
    # Example:
    #   parser = SchemaParser.new('/path/to/rails/app')
    #   parser.parse
    #   # => { articles: { primary_key: 'id', columns: [...], indexes: [...] }, ... }
    #
    #   parser.to_dexie_schema
    #   # => { articles: '++id, created_at, updated_at', comments: '++id, article_id, ...' }
    #
    class SchemaParser
      attr_reader :rails_root, :tables

      SCHEMA_PATHS = %w[
        db/schema.rb
        config/schema.rb
      ].freeze

      def initialize(rails_root)
        @rails_root = rails_root.to_s
        @tables = {}
      end

      # Parse the schema file and extract table definitions
      def parse
        @tables = {}

        schema_path = find_schema_file
        return @tables unless schema_path

        source = File.read(schema_path)
        ast, _ = Ruby2JS.parse(source)
        return @tables unless ast

        extract_tables(ast)
        @tables
      end

      # Generate Dexie.js schema configuration
      def to_dexie_schema(only_tables: nil)
        schema = {}

        tables_to_include = only_tables ? only_tables.map { |t| t.to_s.downcase } : @tables.keys

        tables_to_include.each do |table_name|
          table_name = table_name.to_s
          table = @tables[table_name]
          next unless table

          # Build Dexie index specification
          # ++id for auto-increment primary key
          # then list indexed columns (foreign keys, timestamps)
          indexes = []

          if table[:primary_key]
            indexes << "++#{table[:primary_key]}"
          end

          # Add foreign key columns as indexes
          table[:columns].each do |col|
            if col[:name].end_with?('_id')
              indexes << col[:name]
            end
          end

          # Add timestamps as indexes (useful for ordering)
          %w[created_at updated_at].each do |ts|
            if table[:columns].any? { |c| c[:name] == ts }
              indexes << ts
            end
          end

          schema[table_name] = indexes.join(', ')
        end

        schema
      end

      # Generate JavaScript code for Dexie schema
      def to_dexie_js(only_tables: nil, db_name: 'app_db', version: 1)
        schema = to_dexie_schema(only_tables: only_tables)

        stores = schema.map do |table, indexes|
          "      #{table}: '#{indexes}'"
        end.join(",\n")

        <<~JS
          import Dexie from 'dexie';

          const db = new Dexie('#{db_name}');

          db.version(#{version}).stores({
          #{stores}
          });

          export { db };
        JS
      end

      private

      def find_schema_file
        SCHEMA_PATHS.each do |path|
          full_path = File.join(@rails_root, path)
          return full_path if File.exist?(full_path)
        end
        nil
      end

      def extract_tables(ast)
        walk_ast(ast) do |node|
          # Look for create_table blocks
          next unless node.type == :block

          call = node.children[0]
          next unless call.type == :send
          next unless call.children[0].nil? && call.children[1] == :create_table

          process_create_table(call, node.children[2])
        end
      end

      def walk_ast(node, &block)
        return unless node.respond_to?(:type)

        yield node

        node.children.each { |child| walk_ast(child, &block) }
      end

      def process_create_table(call, body)
        args = call.children[2..]
        return if args.empty?

        table_name = extract_string_value(args[0])
        return unless table_name

        options = extract_hash_options(args[1])
        columns = []

        # Default primary key unless id: false
        primary_key = options[:id] == false ? nil : 'id'

        # Process column definitions in the block body
        if body
          column_nodes = body.type == :begin ? body.children : [body]

          column_nodes.each do |col_node|
            next unless col_node&.type == :send

            col_info = process_column(col_node)
            columns.concat(col_info) if col_info
          end
        end

        @tables[table_name] = {
          name: table_name,
          primary_key: primary_key,
          columns: columns,
          options: options
        }
      end

      def process_column(node)
        target, method, *args = node.children

        # Must be called on t (the table builder)
        return nil unless target&.type == :lvar && target.children[0] == :t

        case method
        when :timestamps
          [
            { name: 'created_at', type: :datetime },
            { name: 'updated_at', type: :datetime }
          ]
        when :references, :belongs_to
          ref_name = extract_string_value(args[0])
          return nil unless ref_name
          [{ name: "#{ref_name}_id", type: :integer, foreign_key: true }]
        else
          col_name = extract_string_value(args[0])
          return nil unless col_name

          options = extract_hash_options(args[1])
          [{ name: col_name, type: method, **options }]
        end
      end

      def extract_string_value(node)
        return nil unless node

        case node.type
        when :str then node.children[0]
        when :sym then node.children[0].to_s
        else nil
        end
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
        else node
        end
      end
    end
  end
end
