require 'ruby2js'
require 'ruby2js/inflector'

module Ruby2JS
  module Filter
    module Rails
      module Schema
        include SEXP

        # SQLite type mapping
        TYPE_MAP = {
          string: 'TEXT',
          text: 'TEXT',
          integer: 'INTEGER',
          bigint: 'INTEGER',
          float: 'REAL',
          decimal: 'REAL',
          boolean: 'INTEGER',
          date: 'TEXT',
          datetime: 'TEXT',
          time: 'TEXT',
          timestamp: 'TEXT',
          binary: 'BLOB',
          json: 'TEXT',
          jsonb: 'TEXT',
        }.freeze

        def initialize(*args)
          @rails_schema = nil
          @rails_tables = []
          @rails_indexes = []
          super
        end

        # Detect ActiveRecord::Schema.define block
        def on_block(node)
          call, args, body = node.children

          # Check for ActiveRecord::Schema.define or ActiveRecord::Schema[version].define
          return super unless schema_define_block?(call)

          @rails_schema = true
          @rails_tables = []
          @rails_indexes = []

          # Process the schema DSL
          process_schema_body(body)

          # Build the Schema module
          result = build_schema_module

          @rails_schema = nil
          @rails_tables = []
          @rails_indexes = []

          result
        end

        private

        def schema_define_block?(node)
          return false unless node&.type == :send

          target, method = node.children[0..1]
          return false unless method == :define

          # Check for ActiveRecord::Schema or ActiveRecord::Schema[version]
          if target&.type == :const
            # ActiveRecord::Schema.define
            return target.children == [s(:const, nil, :ActiveRecord), :Schema]
          elsif target&.type == :send && target.children[1] == :[]
            # ActiveRecord::Schema[7.0].define
            schema_const = target.children[0]
            return schema_const&.type == :const &&
                   schema_const.children == [s(:const, nil, :ActiveRecord), :Schema]
          end

          false
        end

        def process_schema_body(body)
          return unless body

          children = body.type == :begin ? body.children : [body]

          children.each do |child|
            next unless child

            case child.type
            when :block
              process_schema_block(child)
            when :send
              process_schema_send(child)
            end
          end
        end

        def process_schema_block(node)
          call, block_args, body = node.children
          return unless call.type == :send

          target, method, *args = call.children
          return unless target.nil?

          case method
          when :create_table
            process_create_table(args, block_args, body)
          end
        end

        def process_schema_send(node)
          target, method, *args = node.children
          return unless target.nil?

          case method
          when :add_index
            process_add_index(args)
          end
        end

        def process_create_table(args, block_args, body)
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
              type: 'INTEGER',
              constraints: ['PRIMARY KEY', 'AUTOINCREMENT']
            }
          end

          # Process column definitions
          if body
            column_children = body.type == :begin ? body.children : [body]

            column_children.each do |child|
              next unless child&.type == :send

              result = process_column(child, table_name)
              if result
                # Handle single column
                columns << result[:column] if result[:column]
                # Handle multiple columns (timestamps)
                columns.concat(result[:columns]) if result[:columns]
                # Handle foreign keys
                foreign_keys << result[:foreign_key] if result[:foreign_key]
              end
            end
          end

          @rails_tables << {
            name: table_name,
            columns: columns,
            foreign_keys: foreign_keys
          }
        end

        def process_column(node, table_name)
          target, method, *args = node.children

          # Must be called on t (the table builder)
          return nil unless target&.type == :lvar && target.children[0] == :t

          case method
          when :timestamps
            # Add created_at and updated_at columns
            return {
              columns: [
                { name: 'created_at', type: 'TEXT', constraints: [] },
                { name: 'updated_at', type: 'TEXT', constraints: [] }
              ]
            }
          when :references, :belongs_to
            return process_references(args, table_name)
          else
            return process_regular_column(method, args)
          end
        end

        def process_regular_column(type, args)
          return nil if args.empty?

          column_name = extract_string_value(args[0])
          return nil unless column_name

          sql_type = TYPE_MAP[type] || 'TEXT'
          constraints = []

          # Process options
          args[1..-1].each do |arg|
            next unless arg.type == :hash

            arg.children.each do |pair|
              key = pair.children[0]
              value = pair.children[1]
              next unless key.type == :sym

              case key.children[0]
              when :null
                constraints << 'NOT NULL' if value.type == :false
              when :default
                default_value = extract_default_value(value)
                constraints << "DEFAULT #{default_value}" if default_value
              when :limit
                # For string columns, limit doesn't matter in SQLite
              when :precision, :scale
                # Decimal precision/scale not relevant for SQLite
              end
            end
          end

          {
            column: {
              name: column_name,
              type: sql_type,
              constraints: constraints
            }
          }
        end

        def process_references(args, table_name)
          return nil if args.empty?

          ref_name = extract_string_value(args[0])
          return nil unless ref_name

          column_name = "#{ref_name}_id"
          constraints = ['NOT NULL']
          foreign_key = nil

          # Process options
          args[1..-1].each do |arg|
            next unless arg.type == :hash

            arg.children.each do |pair|
              key = pair.children[0]
              value = pair.children[1]
              next unless key.type == :sym

              case key.children[0]
              when :null
                constraints.delete('NOT NULL') if value.type == :true
              when :foreign_key
                if value.type == :true
                  # Infer table name from reference name
                  ref_table = Ruby2JS::Inflector.pluralize(ref_name)
                  foreign_key = {
                    column: column_name,
                    references_table: ref_table,
                    references_column: 'id'
                  }
                elsif value.type == :hash
                  # foreign_key: { to_table: "authors" }
                  value.children.each do |fk_pair|
                    fk_key = fk_pair.children[0]
                    fk_value = fk_pair.children[1]
                    if fk_key.type == :sym && fk_key.children[0] == :to_table
                      foreign_key = {
                        column: column_name,
                        references_table: extract_string_value(fk_value),
                        references_column: 'id'
                      }
                    end
                  end
                end
              when :polymorphic
                # Polymorphic associations add a type column
                # Not fully supported in simple SQL
              end
            end
          end

          {
            column: {
              name: column_name,
              type: 'INTEGER',
              constraints: constraints
            },
            foreign_key: foreign_key
          }
        end

        def process_add_index(args)
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

          index_name = options[:name] || "idx_#{table_name}_#{columns.join('_')}"

          @rails_indexes << {
            table: table_name,
            columns: columns,
            name: index_name,
            unique: options[:unique]
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
              when :primary_key
                options[:primary_key] = extract_string_value(value)
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
          when :str
            "'#{node.children[0].gsub("'", "''")}'"
          when :int, :float
            node.children[0].to_s
          when :true
            '1'
          when :false
            '0'
          when :nil
            'NULL'
          else
            nil
          end
        end

        def build_schema_module
          # Build the create_tables method body
          statements = []

          # Generate CREATE TABLE statements
          @rails_tables.each do |table|
            statements << build_create_table_statement(table)
          end

          # Generate CREATE INDEX statements
          @rails_indexes.each do |index|
            statements << build_create_index_statement(index)
          end

          # Build method body
          method_body = statements.length == 1 ? statements.first : s(:begin, *statements)

          create_tables_method = s(:defs, s(:self), :create_tables,
            s(:args, s(:arg, :db)),
            method_body)

          # Export the module
          process(s(:send, nil, :export,
            s(:module, s(:const, nil, :Schema), create_tables_method)))
        end

        def build_create_table_statement(table)
          # Build column definitions
          column_defs = []

          table[:columns].each do |col|
            col_def = "#{col[:name]} #{col[:type]}"
            col_def += " #{col[:constraints].join(' ')}" if col[:constraints]&.any?
            column_defs << col_def
          end

          # Add timestamps if any column had timestamps: true
          # (handled by detecting t.timestamps in process_column)

          # Check if we need to add timestamps
          has_timestamps = @rails_tables.any? do |t|
            t[:name] == table[:name] && t[:columns].none? { |c| c[:name] == 'created_at' }
          end

          # Add foreign key constraints
          table[:foreign_keys].compact.each do |fk|
            column_defs << "FOREIGN KEY (#{fk[:column]}) REFERENCES #{fk[:references_table]}(#{fk[:references_column]})"
          end

          sql = "CREATE TABLE IF NOT EXISTS #{table[:name]} (\n"
          sql += column_defs.map { |d| "        #{d}" }.join(",\n")
          sql += "\n      )"

          # db.run(%{...})
          s(:send, s(:lvar, :db), :run, s(:str, sql))
        end

        def build_create_index_statement(index)
          unique = index[:unique] ? 'UNIQUE ' : ''
          columns = index[:columns].join(', ')

          sql = "CREATE #{unique}INDEX IF NOT EXISTS #{index[:name]} ON #{index[:table]}(#{columns})"

          s(:send, s(:lvar, :db), :run, s(:str, sql))
        end
      end
    end

    DEFAULTS.push Rails::Schema
  end
end
