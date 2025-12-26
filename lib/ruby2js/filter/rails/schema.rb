require 'ruby2js'
require 'ruby2js/inflector'

module Ruby2JS
  module Filter
    module Rails
      module Schema
        include SEXP

        # No TYPE_MAP here - adapters handle type mapping
        # We keep abstract Rails types: string, text, integer, boolean, datetime, etc.

        def initialize(*args)
          # Note: super must be called first for JS class compatibility
          super
          @rails_schema = nil
          @rails_tables = []
          @rails_indexes = []
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
            # Note: compare children individually for JS compatibility (=== compares references, not values)
            children = target.children
            return children.length == 2 &&
                   children[0]&.type == :const &&
                   children[0].children[0].nil? &&
                   children[0].children[1] == :ActiveRecord &&
                   children[1] == :Schema
          elsif target&.type == :send && target.children[1] == :[]
            # ActiveRecord::Schema[7.0].define
            schema_const = target.children[0]
            return false unless schema_const&.type == :const
            children = schema_const.children
            return children.length == 2 &&
                   children[0]&.type == :const &&
                   children[0].children[0].nil? &&
                   children[0].children[1] == :ActiveRecord &&
                   children[1] == :Schema
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
                # Handle single column
                columns << result[:column] if result[:column]
                # Handle multiple columns (timestamps)
                # Note: use push(*arr) for JS compatibility (JS concat returns new array, doesn't modify in place)
                columns.push(*result[:columns]) if result[:columns]
                # Handle foreign keys
                foreign_keys << result[:foreign_key] if result[:foreign_key]
              end
            end
          end

          # Note: use push instead of << for JS compatibility (autoreturn + << = bitwise shift)
          @rails_tables.push({
            name: table_name,
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
            # Add created_at and updated_at columns
            return {
              columns: [
                { name: 'created_at', type: 'datetime' },
                { name: 'updated_at', type: 'datetime' }
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

          # Keep abstract Rails type (string, text, integer, etc.)
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

          # Process options
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
                # Not fully supported yet
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

          index_name = options[:name] || "idx_#{table_name}_#{columns.join('_')}"

          # Note: use push instead of << for JS compatibility (autoreturn + << = bitwise shift)
          @rails_indexes.push({
            table: table_name,
            columns: columns,
            name: index_name,
            unique: options[:unique]
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
          # Return abstract Ruby values, not SQL-formatted strings
          case node.type
          when :str
            node.children[0]
          when :int, :float
            node.children[0]
          when :true
            true
          when :false
            false
          when :nil
            nil
          else
            nil
          end
        end

        def build_schema_module
          # Build the create_tables method body
          statements = []

          # Generate createTable calls
          @rails_tables.each do |table|
            statements << build_create_table_call(table)
          end

          # Generate addIndex calls
          @rails_indexes.each do |index|
            statements << build_add_index_call(index)
          end

          # Build method body
          method_body = statements.length == 1 ? statements.first : s(:begin, *statements)

          create_tables_method = s(:defs, s(:self), :create_tables,
            s(:args),
            method_body)

          # Import createTable, addIndex from adapter
          import_stmt = s(:send, nil, :import,
            s(:array, s(:const, nil, :createTable), s(:const, nil, :addIndex)),
            s(:str, '../lib/active_record.mjs'))

          schema_module = s(:send, nil, :export,
            s(:module, s(:const, nil, :Schema), create_tables_method))

          process(s(:begin, import_stmt, schema_module))
        end

        def build_create_table_call(table)
          # Build column definitions as array of hashes
          columns_ast = table[:columns].map do |col|
            pairs = [s(:pair, s(:sym, :name), s(:str, col[:name]))]
            pairs << s(:pair, s(:sym, :type), s(:str, col[:type]))
            pairs << s(:pair, s(:sym, :primaryKey), s(:true)) if col[:primaryKey]
            pairs << s(:pair, s(:sym, :autoIncrement), s(:true)) if col[:autoIncrement]
            pairs << s(:pair, s(:sym, :null), col[:null] ? s(:true) : s(:false)) if col.key?(:null)
            pairs << s(:pair, s(:sym, :default), value_to_ast(col[:default])) if col.key?(:default)
            pairs << s(:pair, s(:sym, :limit), s(:int, col[:limit])) if col[:limit]
            pairs << s(:pair, s(:sym, :precision), s(:int, col[:precision])) if col[:precision]
            pairs << s(:pair, s(:sym, :scale), s(:int, col[:scale])) if col[:scale]
            s(:hash, *pairs)
          end

          # Build foreign keys array if present
          fk_ast = table[:foreign_keys].compact.map do |fk|
            s(:hash,
              s(:pair, s(:sym, :column), s(:str, fk[:column])),
              s(:pair, s(:sym, :references), s(:str, fk[:references_table])),
              s(:pair, s(:sym, :primaryKey), s(:str, fk[:references_column])))
          end

          # Build options hash
          options_pairs = []
          options_pairs << s(:pair, s(:sym, :foreignKeys), s(:array, *fk_ast)) if fk_ast.any?

          args = [s(:str, table[:name]), s(:array, *columns_ast)]
          args << s(:hash, *options_pairs) if options_pairs.any?

          s(:send, nil, :createTable, *args)
        end

        def build_add_index_call(index)
          columns_ast = s(:array, *index[:columns].map { |c| s(:str, c) })

          options_pairs = []
          options_pairs << s(:pair, s(:sym, :name), s(:str, index[:name])) if index[:name]
          options_pairs << s(:pair, s(:sym, :unique), s(:true)) if index[:unique]

          args = [s(:str, index[:table]), columns_ast]
          args << s(:hash, *options_pairs) if options_pairs.any?

          s(:send, nil, :addIndex, *args)
        end

        def value_to_ast(value)
          case value
          when String then s(:str, value)
          when Integer then s(:int, value)
          when Float then s(:float, value)
          when true then s(:true)
          when false then s(:false)
          when nil then s(:nil)
          else s(:nil)
          end
        end
      end
    end

    DEFAULTS.push Rails::Schema
  end
end
