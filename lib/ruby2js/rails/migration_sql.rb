# frozen_string_literal: true

# Generates SQL from Rails migration files for D1 and other SQL databases
# Uses Ruby2JS's parser to parse the migration Ruby code

require 'ruby2js'
require 'ruby2js/inflector'

module Ruby2JS
  module Rails
    class MigrationSQL
      class << self
        # Generate SQL for all migrations in a directory
        # Returns a hash with :sql (combined SQL) and :migrations (array of parsed migrations)
        def generate_all(migrate_dir)
          return { sql: '', migrations: [] } unless File.exist?(migrate_dir)

          migrations = []
          sql_parts = []

          sql_parts << "-- Ruby2JS Generated Migrations"
          sql_parts << "-- Generated at: #{Time.now.utc}"
          sql_parts << ""
          sql_parts << "-- Schema migrations tracking table"
          sql_parts << "CREATE TABLE IF NOT EXISTS schema_migrations (version TEXT PRIMARY KEY);"
          sql_parts << ""

          Dir.glob(File.join(migrate_dir, '*.rb')).sort.each do |path|
            basename = File.basename(path, '.rb')
            version = basename.split('_').first

            migration = parse_migration(path)
            next unless migration

            sql = generate_sql(migration[:statements], version)
            sql_parts << sql if sql && !sql.empty?

            migrations << { version: version, filename: basename }
          end

          { sql: sql_parts.join("\n"), migrations: migrations }
        end

        # Parse a single migration file and extract statements
        def parse_migration(path)
          source = File.read(path)
          ast, _ = Ruby2JS.parse(source)
          return nil unless ast

          statements = []
          extract_statements(ast, statements)

          { path: path, statements: statements }
        end

        # Generate SQL from migration statements
        def generate_sql(statements, version)
          return '' if statements.empty?

          sql_lines = []
          sql_lines << "-- Migration: #{version}"

          statements.each do |stmt|
            case stmt[:type]
            when :create_table
              sql_lines << create_table_sql(stmt)
            when :add_index
              sql_lines << add_index_sql(stmt)
            when :add_column
              sql_lines << add_column_sql(stmt)
            when :remove_column
              sql_lines << remove_column_sql(stmt)
            when :drop_table
              sql_lines << drop_table_sql(stmt)
            end
          end

          # Add version tracking
          sql_lines << "INSERT INTO schema_migrations (version) VALUES ('#{version}') ON CONFLICT DO NOTHING;"
          sql_lines << ""

          sql_lines.join("\n")
        end

        private

        def extract_statements(node, statements)
          return unless node

          case node.type
          when :class
            # Check if this is a migration class
            name, parent, body = node.children
            if migration_class?(parent)
              extract_from_body(body, statements)
            end
          when :begin
            node.children.each { |child| extract_statements(child, statements) }
          end
        end

        def migration_class?(node)
          return false unless node

          if node.type == :send && node.children[1] == :[]
            const = node.children[0]
            return migration_const?(const)
          elsif node.type == :const
            return migration_const?(node)
          end

          false
        end

        def migration_const?(node)
          return false unless node&.type == :const
          children = node.children
          return false unless children.length == 2

          parent = children[0]
          name = children[1]

          parent&.type == :const &&
            parent.children[0].nil? &&
            parent.children[1] == :ActiveRecord &&
            name == :Migration
        end

        def extract_from_body(body, statements)
          return unless body

          children = body.type == :begin ? body.children : [body]

          children.each do |child|
            next unless child

            if child.type == :def
              method_name = child.children[0]
              if method_name == :change || method_name == :up
                extract_from_method(child.children[2], statements)
              end
            end
          end
        end

        def extract_from_method(body, statements)
          return unless body

          children = body.type == :begin ? body.children : [body]

          children.each do |child|
            next unless child

            case child.type
            when :block
              extract_block(child, statements)
            when :send
              extract_send(child, statements)
            end
          end
        end

        def extract_block(node, statements)
          call, block_args, body = node.children
          return unless call.type == :send

          target, method, *args = call.children
          return unless target.nil?

          case method
          when :create_table
            extract_create_table(args, block_args, body, statements)
          end
        end

        def extract_send(node, statements)
          target, method, *args = node.children
          return unless target.nil?

          case method
          when :add_index
            extract_add_index(args, statements)
          when :add_column
            extract_add_column(args, statements)
          when :remove_column
            extract_remove_column(args, statements)
          when :drop_table
            extract_drop_table(args, statements)
          end
        end

        def extract_create_table(args, block_args, body, statements)
          return if args.empty?

          table_name = extract_string_value(args[0])
          return unless table_name

          options = extract_table_options(args)
          columns = []
          foreign_keys = []

          # Add primary key unless id: false
          unless options[:id] == false
            columns << {
              name: 'id',
              type: 'integer',
              primaryKey: true,
              autoIncrement: true
            }
          end

          # Process column definitions
          if body
            column_children = body.type == :begin ? body.children : [body]

            column_children.each do |child|
              next unless child&.type == :send

              result = extract_column(child, table_name)
              if result
                columns << result[:column] if result[:column]
                columns.push(*result[:columns]) if result[:columns]
                foreign_keys << result[:foreign_key] if result[:foreign_key]
              end
            end
          end

          statements << {
            type: :create_table,
            table: table_name,
            columns: columns,
            foreign_keys: foreign_keys
          }
        end

        def extract_column(node, table_name)
          target, method, *args = node.children

          return nil unless target&.type == :lvar && target.children[0] == :t

          case method
          when :timestamps
            {
              columns: [
                { name: 'created_at', type: 'datetime', null: false },
                { name: 'updated_at', type: 'datetime', null: false }
              ]
            }
          when :references, :belongs_to
            extract_references(args, table_name)
          else
            extract_regular_column(method, args)
          end
        end

        def extract_regular_column(type, args)
          return nil if args.empty?

          column_name = extract_string_value(args[0])
          return nil unless column_name

          column = {
            name: column_name,
            type: type.to_s
          }

          args[1..-1].each do |arg|
            next unless arg.type == :hash

            arg.children.each do |pair|
              key = pair.children[0]
              value = pair.children[1]
              next unless key.type == :sym

              case key.children[0]
              when :null
                column[:null] = (value.type != :false)
              when :default
                column[:default] = extract_default_value(value)
              when :limit
                column[:limit] = value.children[0] if value.type == :int
              end
            end
          end

          { column: column }
        end

        def extract_references(args, table_name)
          return nil if args.empty?

          ref_name = extract_string_value(args[0])
          return nil unless ref_name

          column_name = "#{ref_name}_id"
          column = {
            name: column_name,
            type: 'integer',
            null: false
          }
          foreign_key = nil

          args[1..-1].each do |arg|
            next unless arg.type == :hash

            arg.children.each do |pair|
              key = pair.children[0]
              value = pair.children[1]
              next unless key.type == :sym

              case key.children[0]
              when :null
                column[:null] = true if value.type == :true
              when :foreign_key
                if value.type == :true
                  ref_table = Ruby2JS::Inflector.pluralize(ref_name)
                  foreign_key = {
                    column: column_name,
                    references_table: ref_table,
                    references_column: 'id'
                  }
                end
              end
            end
          end

          { column: column, foreign_key: foreign_key }
        end

        def extract_add_index(args, statements)
          return if args.length < 2

          table_name = extract_string_value(args[0])
          return unless table_name

          columns = if args[1].type == :array
                      args[1].children.map { |c| extract_string_value(c) }.compact
                    else
                      [extract_string_value(args[1])].compact
                    end

          return if columns.empty?

          options = {}
          args[2..-1].each do |arg|
            next unless arg&.type == :hash

            arg.children.each do |pair|
              key = pair.children[0]
              value = pair.children[1]
              next unless key.type == :sym

              case key.children[0]
              when :name
                options[:name] = extract_string_value(value)
              when :unique
                options[:unique] = value.type == :true
              end
            end
          end

          statements << {
            type: :add_index,
            table: table_name,
            columns: columns,
            options: options
          }
        end

        def extract_add_column(args, statements)
          return if args.length < 3

          table_name = extract_string_value(args[0])
          column_name = extract_string_value(args[1])
          column_type = extract_string_value(args[2])

          return unless table_name && column_name && column_type

          statements << {
            type: :add_column,
            table: table_name,
            column: column_name,
            column_type: column_type
          }
        end

        def extract_remove_column(args, statements)
          return if args.length < 2

          table_name = extract_string_value(args[0])
          column_name = extract_string_value(args[1])

          return unless table_name && column_name

          statements << {
            type: :remove_column,
            table: table_name,
            column: column_name
          }
        end

        def extract_drop_table(args, statements)
          return if args.empty?

          table_name = extract_string_value(args[0])
          return unless table_name

          statements << {
            type: :drop_table,
            table: table_name
          }
        end

        def extract_table_options(args)
          options = {}

          args[1..-1].each do |arg|
            next unless arg&.type == :hash

            arg.children.each do |pair|
              key = pair.children[0]
              value = pair.children[1]
              next unless key.type == :sym

              case key.children[0]
              when :id
                options[:id] = value.type != :false
              end
            end
          end

          options
        end

        def extract_string_value(node)
          case node&.type
          when :str then node.children[0]
          when :sym then node.children[0].to_s
          else nil
          end
        end

        def extract_default_value(node)
          case node.type
          when :str then node.children[0]
          when :int, :float then node.children[0]
          when :true then true
          when :false then false
          when :nil then nil
          else nil
          end
        end

        # SQL generation methods

        def create_table_sql(stmt)
          columns_sql = stmt[:columns].map do |col|
            column_def_sql(col)
          end

          # Add foreign key constraints
          stmt[:foreign_keys].compact.each do |fk|
            columns_sql << "FOREIGN KEY (#{fk[:column]}) REFERENCES #{fk[:references_table]}(#{fk[:references_column]})"
          end

          "CREATE TABLE IF NOT EXISTS #{stmt[:table]} (\n  #{columns_sql.join(",\n  ")}\n);"
        end

        def column_def_sql(col)
          parts = [col[:name]]
          parts << sql_type(col[:type])

          if col[:primaryKey]
            parts << "PRIMARY KEY"
            parts << "AUTOINCREMENT" if col[:autoIncrement]
          end

          if col.key?(:null) && col[:null] == false
            parts << "NOT NULL"
          end

          if col.key?(:default)
            parts << "DEFAULT #{sql_value(col[:default])}"
          end

          parts.join(' ')
        end

        def sql_type(type)
          case type.to_s
          when 'string' then 'TEXT'
          when 'text' then 'TEXT'
          when 'integer' then 'INTEGER'
          when 'float', 'decimal' then 'REAL'
          when 'boolean' then 'INTEGER'
          when 'datetime', 'timestamp' then 'TEXT'
          when 'date' then 'TEXT'
          when 'time' then 'TEXT'
          when 'binary', 'blob' then 'BLOB'
          else 'TEXT'
          end
        end

        def sql_value(value)
          case value
          when String then "'#{value.gsub("'", "''")}'"
          when Integer, Float then value.to_s
          when true then '1'
          when false then '0'
          when nil then 'NULL'
          else "'#{value}'"
          end
        end

        def add_index_sql(stmt)
          unique = stmt[:options][:unique] ? 'UNIQUE ' : ''
          name = stmt[:options][:name] || "index_#{stmt[:table]}_on_#{stmt[:columns].join('_')}"
          columns = stmt[:columns].join(', ')

          "CREATE #{unique}INDEX IF NOT EXISTS #{name} ON #{stmt[:table]} (#{columns});"
        end

        def add_column_sql(stmt)
          "ALTER TABLE #{stmt[:table]} ADD COLUMN #{stmt[:column]} #{sql_type(stmt[:column_type])};"
        end

        def remove_column_sql(stmt)
          # SQLite doesn't support DROP COLUMN before 3.35.0
          # D1 uses SQLite, so we need to handle this carefully
          "-- Note: SQLite may not support DROP COLUMN\n-- ALTER TABLE #{stmt[:table]} DROP COLUMN #{stmt[:column]};"
        end

        def drop_table_sql(stmt)
          "DROP TABLE IF EXISTS #{stmt[:table]};"
        end
      end
    end
  end
end
