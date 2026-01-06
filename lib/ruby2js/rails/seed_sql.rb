# frozen_string_literal: true

# Generates SQL INSERT statements from Rails seed files for D1
# Uses Ruby2JS's parser to parse the seed Ruby code

require 'ruby2js'
require 'ruby2js/inflector'

module Ruby2JS
  module Rails
    class SeedSQL
      # Generate SQL for a seeds.rb file
      # Returns a hash with :sql (SQL statements) and :inserts (count)
      def self.generate(seeds_path)
        return { sql: '', inserts: 0 } unless File.exist?(seeds_path)

        source = File.read(seeds_path)
        ast, _ = Ruby2JS.parse(source)
        return { sql: '', inserts: 0 } unless ast

        inserts = []
        guard_model = nil

        # Extract guard condition (e.g., "return if Message.count > 0")
        guard_model = extract_guard(ast)

        # Extract create statements
        extract_creates(ast, inserts)

        return { sql: '', inserts: 0 } if inserts.empty?

        sql_parts = []
        sql_parts << "-- Ruby2JS Generated Seeds"
        sql_parts << "-- Generated at: #{Time.now.utc}"
        sql_parts << ""
        sql_parts << "-- Seed tracking table (like schema_migrations)"
        sql_parts << "CREATE TABLE IF NOT EXISTS _seeds_applied (id INTEGER PRIMARY KEY);"
        sql_parts << ""

        inserts.each do |insert|
          sql_parts << generate_insert_sql(insert)
        end

        sql_parts << ""
        sql_parts << "-- Mark seeds as applied"
        sql_parts << "INSERT INTO _seeds_applied (id) VALUES (1) ON CONFLICT DO NOTHING;"

        { sql: sql_parts.join("\n"), inserts: inserts.length }
      end

      # Extract the guard model from "return if Model.count > 0"
      def self.extract_guard(node)
        return nil unless node

        case node.type
        when :if
          # Check for: return if Model.count > 0
          cond, then_body, else_body = node.children
          if then_body.nil? && else_body&.type == :return
            # This is "return if <cond>" format
            return extract_count_model(cond)
          elsif then_body&.type == :return && else_body.nil?
            return extract_count_model(cond)
          end
        when :begin
          # Check each statement
          node.children.each do |child|
            result = extract_guard(child)
            return result if result
          end
        end

        nil
      end

      # Extract model name from "Model.count > 0" or "Model.count.positive?"
      def self.extract_count_model(node)
        return nil unless node

        case node.type
        when :send
          target, method, *args = node.children

          # Model.count > 0
          if method == :> && args.first&.type == :int && args.first.children.first == 0
            if target&.type == :send && target.children[1] == :count
              model_node = target.children[0]
              return model_node.children[1].to_s if model_node&.type == :const
            end
          end

          # Model.count.positive?
          if method == :positive? && target&.type == :send && target.children[1] == :count
            model_node = target.children[0]
            return model_node.children[1].to_s if model_node&.type == :const
          end
        end

        nil
      end

      # Extract all Model.create/create! calls from the AST
      def self.extract_creates(node, inserts)
        return unless node

        case node.type
        when :send
          target, method, *args = node.children

          # Look for Model.create or Model.create!
          if [:create, :create!].include?(method) && target&.type == :const
            model_name = target.children[1].to_s
            # tableize: underscore + pluralize (e.g., "Message" -> "messages")
            underscored = model_name.gsub(/([a-z])([A-Z])/, '\1_\2').downcase
            table_name = Ruby2JS::Inflector.pluralize(underscored)

            # Extract attributes from hash argument
            if args.first&.type == :hash
              attributes = extract_hash(args.first)
              inserts << { table: table_name, attributes: attributes }
            end
          end
        when :begin, :block, :if
          node.children.each { |child| extract_creates(child, inserts) if child }
        end
      end

      # Extract key-value pairs from a hash node
      def self.extract_hash(node)
        attributes = {}

        node.children.each do |pair|
          next unless pair.type == :pair

          key_node, value_node = pair.children

          key = case key_node.type
                when :sym then key_node.children[0].to_s
                when :str then key_node.children[0]
                else next
                end

          value = extract_value(value_node)
          attributes[key] = value
        end

        attributes
      end

      # Extract a Ruby value from an AST node
      def self.extract_value(node)
        case node.type
        when :str then node.children[0]
        when :int then node.children[0]
        when :float then node.children[0]
        when :true then true
        when :false then false
        when :nil then nil
        else nil
        end
      end

      # Generate SQL INSERT statement
      # Uses WHERE NOT EXISTS on _seeds_applied to skip if seeds already ran
      def self.generate_insert_sql(insert)
        table = insert[:table]
        attrs = insert[:attributes].dup

        # Add timestamps
        attrs['created_at'] = :now
        attrs['updated_at'] = :now

        columns = attrs.keys
        values = attrs.values.map { |v| sql_value(v) }

        # Check _seeds_applied table, not the data table
        "INSERT INTO #{table} (#{columns.join(', ')}) " \
          "SELECT #{values.join(', ')} " \
          "WHERE NOT EXISTS (SELECT 1 FROM _seeds_applied);"
      end

      def self.sql_value(value)
        case value
        when String then "'#{value.gsub("'", "''")}'"
        when Integer, Float then value.to_s
        when true then '1'
        when false then '0'
        when nil then 'NULL'
        when :now then "datetime('now')"
        else "'#{value}'"
        end
      end
    end
  end
end
