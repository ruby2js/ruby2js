require 'ruby2js'
require 'ruby2js/inflector'

module Ruby2JS
  module Filter
    module Rails
      module Migration
        include SEXP

        def initialize(*args)
          super
          @rails_migration = nil
          @migration_statements = []
        end

        # Detect class CreateXxx < ActiveRecord::Migration[x.x]
        def on_class(node)
          name, parent, *body = node.children

          # Check for ActiveRecord::Migration inheritance
          return super unless migration_class?(parent)

          @rails_migration = name.children[1].to_s
          @migration_statements = []

          # Process class body to find change/up method
          process_migration_body(body.first)

          result = build_migration_module

          @rails_migration = nil
          @migration_statements = []

          result
        end

        private

        def migration_class?(node)
          return false unless node

          # ActiveRecord::Migration[7.0] or ActiveRecord::Migration
          if node.type == :send && node.children[1] == :[]
            # ActiveRecord::Migration[version]
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

        def process_migration_body(body)
          return unless body

          children = body.type == :begin ? body.children : [body]

          children.each do |child|
            next unless child

            # Look for def change or def up
            if child.type == :def
              method_name = child.children[0]
              if method_name == :change || method_name == :up
                process_migration_method(child.children[2])
              end
            end
          end
        end

        def process_migration_method(body)
          return unless body

          children = body.type == :begin ? body.children : [body]

          children.each do |child|
            next unless child

            case child.type
            when :block
              process_migration_block(child)
            when :send
              process_migration_send(child)
            end
          end
        end

        def process_migration_block(node)
          call, block_args, body = node.children
          return unless call.type == :send

          target, method, *args = call.children
          return unless target.nil?

          case method
          when :create_table
            process_create_table(args, block_args, body)
          end
        end

        def process_migration_send(node)
          target, method, *args = node.children
          return unless target.nil?

          case method
          when :add_index
            process_add_index(args)
          when :add_column
            process_add_column(args)
          when :remove_column
            process_remove_column(args)
          when :drop_table
            process_drop_table(args)
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

              result = process_column(child, table_name)
              if result
                columns << result[:column] if result[:column]
                columns.push(*result[:columns]) if result[:columns]
                foreign_keys << result[:foreign_key] if result[:foreign_key]
              end
            end
          end

          @migration_statements.push({
            type: :create_table,
            table: table_name,
            columns: columns,
            foreign_keys: foreign_keys
          })
        end

        def process_column(node, table_name)
          target, method, *args = node.children

          # Must be called on t (the table builder)
          return nil unless target&.type == :lvar && target.children[0] == :t

          case method
          when :timestamps
            return {
              columns: [
                { name: 'created_at', type: 'datetime', null: false },
                { name: 'updated_at', type: 'datetime', null: false }
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

          column = {
            name: column_name,
            type: type.to_s
          }

          # Process options
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
              when :precision
                column[:precision] = value.children[0] if value.type == :int
              when :scale
                column[:scale] = value.children[0] if value.type == :int
              end
            end
          end

          { column: column }
        end

        def process_references(args, table_name)
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

          {
            column: column,
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

          @migration_statements.push({
            type: :add_index,
            table: table_name,
            columns: columns,
            options: options
          })
        end

        def process_add_column(args)
          return if args.length < 3

          table_name = extract_string_value(args[0])
          column_name = extract_string_value(args[1])
          column_type = extract_string_value(args[2])

          return unless table_name && column_name && column_type

          @migration_statements.push({
            type: :add_column,
            table: table_name,
            column: column_name,
            column_type: column_type
          })
        end

        def process_remove_column(args)
          return if args.length < 2

          table_name = extract_string_value(args[0])
          column_name = extract_string_value(args[1])

          return unless table_name && column_name

          @migration_statements.push({
            type: :remove_column,
            table: table_name,
            column: column_name
          })
        end

        def process_drop_table(args)
          return if args.empty?

          table_name = extract_string_value(args[0])
          return unless table_name

          @migration_statements.push({
            type: :drop_table,
            table: table_name
          })
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

        def build_migration_module
          # Build the up function body
          statements = @migration_statements.map do |stmt|
            build_statement_call(stmt)
          end

          method_body = statements.length == 1 ? statements.first : s(:begin, *statements)

          # Export migration object with version and up function
          up_method = s(:pair, s(:sym, :up),
            s(:block,
              s(:send, nil, :async),
              s(:args),
              method_body))

          # Build tableSchemas for Dexie (e.g., { articles: '++id, title, created_at' })
          table_schemas_pairs = @migration_statements
            .select { |stmt| stmt[:type] == :create_table }
            .map do |stmt|
              # Build Dexie schema string: '++id, column1, column2, ...'
              schema_parts = stmt[:columns].map do |col|
                if col[:primaryKey] && col[:autoIncrement]
                  "++#{col[:name]}"
                elsif col[:primaryKey]
                  "&#{col[:name]}"
                else
                  col[:name]
                end
              end
              s(:pair, s(:sym, stmt[:table].to_sym), s(:str, schema_parts.join(', ')))
            end

          migration_parts = [up_method]
          if table_schemas_pairs.any?
            migration_parts << s(:pair, s(:sym, :tableSchemas), s(:hash, *table_schemas_pairs))
          end

          migration_obj = s(:hash, *migration_parts)

          export_stmt = s(:send, nil, :export,
            s(:casgn, nil, :migration, migration_obj))

          # Import createTable, addIndex, addColumn, etc. from adapter
          import_stmt = s(:send, nil, :import,
            s(:array,
              s(:const, nil, :createTable),
              s(:const, nil, :addIndex),
              s(:const, nil, :addColumn),
              s(:const, nil, :removeColumn),
              s(:const, nil, :dropTable)),
            s(:str, '../../lib/active_record.mjs'))

          process(s(:begin, import_stmt, export_stmt))
        end

        def build_statement_call(stmt)
          case stmt[:type]
          when :create_table
            build_create_table_call(stmt)
          when :add_index
            build_add_index_call(stmt)
          when :add_column
            build_add_column_call(stmt)
          when :remove_column
            build_remove_column_call(stmt)
          when :drop_table
            build_drop_table_call(stmt)
          end
        end

        def build_create_table_call(stmt)
          columns_ast = stmt[:columns].map do |col|
            pairs = [s(:pair, s(:sym, :name), s(:str, col[:name]))]
            pairs << s(:pair, s(:sym, :type), s(:str, col[:type]))
            pairs << s(:pair, s(:sym, :primaryKey), s(:true)) if col[:primaryKey]
            pairs << s(:pair, s(:sym, :autoIncrement), s(:true)) if col[:autoIncrement]
            pairs << s(:pair, s(:sym, :null), col[:null] ? s(:true) : s(:false)) if col.key?(:null)
            pairs << s(:pair, s(:sym, :default), value_to_ast(col[:default])) if col.key?(:default)
            s(:hash, *pairs)
          end

          fk_ast = stmt[:foreign_keys].compact.map do |fk|
            s(:hash,
              s(:pair, s(:sym, :column), s(:str, fk[:column])),
              s(:pair, s(:sym, :references), s(:str, fk[:references_table])),
              s(:pair, s(:sym, :primaryKey), s(:str, fk[:references_column])))
          end

          options_pairs = []
          options_pairs << s(:pair, s(:sym, :foreignKeys), s(:array, *fk_ast)) if fk_ast.any?

          args = [s(:str, stmt[:table]), s(:array, *columns_ast)]
          args << s(:hash, *options_pairs) if options_pairs.any?

          s(:send, nil, :await, s(:send, nil, :createTable, *args))
        end

        def build_add_index_call(stmt)
          columns_ast = s(:array, *stmt[:columns].map { |c| s(:str, c) })

          options_pairs = []
          options_pairs << s(:pair, s(:sym, :name), s(:str, stmt[:options][:name])) if stmt[:options][:name]
          options_pairs << s(:pair, s(:sym, :unique), s(:true)) if stmt[:options][:unique]

          args = [s(:str, stmt[:table]), columns_ast]
          args << s(:hash, *options_pairs) if options_pairs.any?

          s(:send, nil, :await, s(:send, nil, :addIndex, *args))
        end

        def build_add_column_call(stmt)
          s(:send, nil, :await,
            s(:send, nil, :addColumn,
              s(:str, stmt[:table]),
              s(:str, stmt[:column]),
              s(:str, stmt[:column_type])))
        end

        def build_remove_column_call(stmt)
          s(:send, nil, :await,
            s(:send, nil, :removeColumn,
              s(:str, stmt[:table]),
              s(:str, stmt[:column])))
        end

        def build_drop_table_call(stmt)
          s(:send, nil, :await,
            s(:send, nil, :dropTable,
              s(:str, stmt[:table])))
        end

        def value_to_ast(value)
          if value == true
            s(:true)
          elsif value == false
            s(:false)
          elsif value.nil?
            s(:nil)
          elsif value.is_a?(String)
            s(:str, value)
          elsif value.is_a?(Integer)
            s(:int, value)
          elsif value.is_a?(Float)
            s(:float, value)
          else
            s(:nil)
          end
        end
      end
    end

    DEFAULTS.push Rails::Migration
  end
end
