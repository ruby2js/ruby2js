# frozen_string_literal: true

# Combiner filter - merges reopened modules and classes
#
# Ruby allows reopening modules and classes to add methods:
#   module Foo
#     def bar; end
#   end
#   module Foo
#     def baz; end
#   end
#
# JavaScript doesn't support this pattern. This filter merges
# all definitions with the same name into a single definition.
#
# Run this filter AFTER the require filter so that inlined
# files get their classes/modules merged with the main file.

require 'ruby2js'

module Ruby2JS
  module Filter
    module Combiner
      include SEXP

      # Ensure combiner runs after ESM filter so that import statements
      # have been converted to :import nodes before we try to deduplicate them
      def self.reorder(filters)
        esm_filter = defined?(Ruby2JS::Filter::ESM) ? Ruby2JS::Filter::ESM : nil
        return filters unless esm_filter && filters.include?(esm_filter)

        combiner_index = filters.index(Ruby2JS::Filter::Combiner)
        esm_index = filters.index(esm_filter)

        # Use explicit nil check - in JS, index 0 is falsy so `!index` would be true
        return filters if combiner_index.nil? || esm_index.nil?
        return filters if combiner_index > esm_index  # Already after ESM

        # Move combiner to after ESM
        filters = filters.dup
        filters.delete_at(combiner_index)
        # esm_index may have shifted if combiner was before it
        esm_index = filters.index(esm_filter)
        filters.insert(esm_index + 1, Ruby2JS::Filter::Combiner)

        filters
      end

      # Process the entire AST after all children are processed
      # We need to find and merge duplicate module/class definitions
      # Note: Only handles statement-level :begin, not expression grouping
      def on_begin(node)
        # Only process if this is a top-level statement sequence (multiple children)
        # Single-child begin nodes are used for expression grouping (like `!(a && b)`)
        # and should be left alone to preserve semantics
        return super if node.children.length <= 1

        children = process_all(node.children)
        children = merge_definitions(children)
        children = children.compact
        return nil if children.empty?
        return children.first if children.length == 1
        node.updated(nil, children)
      end

      private

      # Flatten nested :begin nodes to get all children at the same level
      # This handles cases where require filter wraps content in :begin nodes
      def flatten_begins(nodes)
        result = []
        nodes.each do |node|
          next unless node
          if node.type == :begin
            # Recursively flatten nested begins
            # Note: Use push with splat instead of concat - Ruby's concat modifies
            # in place but JS concat returns a new array
            result.push(*flatten_begins(node.children))
          else
            result << node
          end
        end
        result
      end

      # Merge duplicate module/class definitions and deduplicate imports
      def merge_definitions(nodes)
        # Flatten any nested :begin nodes first
        nodes = flatten_begins(nodes)

        # Track definitions by their full name (including nesting)
        definitions = {}  # name => [index, node]
        # Track imports by module path for deduplication
        imports = {}  # path => [index, node]
        result = []

        nodes.each_with_index do |node, index|
          next unless node

          if [:module, :class].include?(node.type)
            name_key = definition_key(node)

            if definitions[name_key]
              # Merge into existing definition
              orig_index, orig_node = definitions[name_key]
              merged = merge_definition(orig_node, node)
              result[orig_index] = merged
              definitions[name_key] = [orig_index, merged]
              # Don't add this node to result (it's been merged)
            else
              # First occurrence - track it
              definitions[name_key] = [result.length, node]
              result << node
            end
          elsif node.type == :import || is_import_send?(node)
            import_key = import_path(node)

            if imports[import_key]
              # Merge into existing import
              orig_index, orig_node = imports[import_key]
              merged = merge_imports(orig_node, node)
              result[orig_index] = merged
              imports[import_key] = [orig_index, merged]
              # Don't add this node to result (it's been merged)
            else
              # First occurrence - track it
              imports[import_key] = [result.length, node]
              result << node
            end
          else
            result << node
          end
        end

        result
      end

      # Generate a unique key for a module/class definition
      def definition_key(node)
        const_node = node.children[0]
        name_parts = []

        # Walk const chain to get full name (e.g., Ruby2JS::Converter)
        while const_node&.type == :const
          name_parts.unshift(const_node.children[1])
          const_node = const_node.children[0]
        end

        "#{node.type}:#{name_parts.join('::')}"
      end

      # Merge two module or class definitions
      def merge_definition(original, reopened)
        # Use array indexing instead of destructuring to avoid
        # JS block-scoping issues (let in if/else creates new scope)
        orig_name = original.children[0]

        if original.type == :class
          # class has 3 children: name, superclass, body
          orig_super = original.children[1]
          orig_body = original.children[2]
          reopen_super = reopened.children[1]
          reopen_body = reopened.children[2]
          superclass = orig_super || reopen_super
        else
          # module has 2 children: name, body
          orig_body = original.children[1]
          reopen_body = reopened.children[1]
          superclass = nil
        end

        # Merge bodies
        orig_children = body_children(orig_body)
        reopen_children = body_children(reopen_body)

        # Recursively merge any nested modules/classes
        # Note: Use splat instead of + for JS compatibility
        # Ruby's array + is not the same as JS's + operator
        merged_children = merge_definitions([*orig_children, *reopen_children])

        # Reorder: put class variable assignments (cvasgn) first
        # JavaScript requires static fields to be declared before use
        merged_children = reorder_class_body(merged_children)

        # Create merged body
        merged_body = case merged_children.length
                      when 0 then nil
                      when 1 then merged_children.first
                      else s(:begin, *merged_children)
                      end

        if original.type == :class
          s(:class, orig_name, superclass, merged_body)
        else
          s(:module, orig_name, merged_body)
        end
      end

      # Extract children from a body node
      def body_children(body)
        return [] if body.nil?
        # Note: Don't use .to_a here - children is already an array,
        # and JS Object.prototype.to_a returns entries not the array itself
        return body.children if body.type == :begin
        [body]
      end

      # Check if a :send node is an import statement
      # e.g., (send nil :import (const nil :React) (hash (pair (sym :from) (str "react"))))
      def is_import_send?(node)
        node.type == :send &&
          node.children[0].nil? &&
          node.children[1] == :import
      end

      # Extract the module path from an import node for deduplication
      # Handles both :import nodes and :send nodes with :import method
      def import_path(node)
        if node.type == :send && node.children[1] == :import
          # :send import - look for hash with :from key
          hash_node = node.children.find { |c| c.respond_to?(:type) && c.type == :hash }
          if hash_node
            from_pair = hash_node.children.find { |p| p.children[0].children[0] == :from }
            return from_pair.children[1].children[0] if from_pair
          end
          # Fallback to string argument
          str_node = node.children.find { |c| c.respond_to?(:type) && c.type == :str }
          return str_node.children[0] if str_node
          return node.to_s
        end

        # :import node
        path = node.children[0]
        if path.is_a?(Array)
          # Find the 'from:' pair
          # Note: Use explicit guards instead of rescue - the rescue modifier
          # transpiles to try/catch without return statements in JS
          from_pair = path.find do |p|
            next false unless p.respond_to?(:type) && p.type == :pair
            next false unless p.children[0].respond_to?(:children)
            p.children[0].children[0] == :from
          end
          from_pair ? from_pair.children[1].children[0] : path[0].to_s
        elsif path.is_a?(String)
          path
        else
          path.to_s
        end
      end

      # Merge two import statements for the same module
      # Combines default imports and named imports
      def merge_imports(orig, new_import)
        # Extract path and imports from both nodes
        orig_path = orig.children[0]
        orig_imports = orig.children[1..-1]
        new_imports = new_import.children[1..-1]

        # If both are identical (same path, same imports), just return original
        return orig if orig_imports == new_imports

        # If one has no imports (side-effect import), prefer the one with imports
        return orig if new_imports.empty?
        return new_import if orig_imports.empty?

        # Merge imports - combine default and named imports
        merged_imports = merge_import_specifiers(orig_imports, new_imports)

        s(:import, orig_path, *merged_imports)
      end

      # Merge import specifiers (default imports and named imports)
      def merge_import_specifiers(orig, new_specs)
        # Separate default imports (single const) from named imports (arrays)
        orig_default = orig.find { |i| !i.is_a?(Array) && i.respond_to?(:type) && i.type == :const }
        new_default = new_specs.find { |i| !i.is_a?(Array) && i.respond_to?(:type) && i.type == :const }

        orig_named = orig.find { |i| i.is_a?(Array) }
        new_named = new_specs.find { |i| i.is_a?(Array) }

        result = []

        # Use the default import from either (they should be the same if both exist)
        result << (orig_default || new_default) if orig_default || new_default

        # Merge named imports
        if orig_named || new_named
          # Use splat for JS-compatible array concatenation
          all_named = [*(orig_named || []), *(new_named || [])]
          # Deduplicate by const name
          seen = {}
          unique_named = all_named.select do |spec|
            next false unless spec.respond_to?(:type)
            name = spec.children[1]
            if seen[name]
              false
            else
              seen[name] = true
              true
            end
          end
          result << unique_named unless unique_named.empty?
        end

        result
      end

      # Reorder class body: static fields (cvasgn) must come before
      # methods that use them, since JavaScript evaluates class body
      # in order (unlike Ruby where class variables are hoisted)
      def reorder_class_body(children)
        # Partition into class variable assignments and everything else
        cvasgns, others = children.partition do |node|
          node&.type == :cvasgn
        end

        # Class variables first, then everything else
        # Use splat for JS-compatible array concatenation
        [*cvasgns, *others]
      end
    end

    # NOTE: Combiner is NOT added to DEFAULTS because it's specifically
    # for self-hosting scenarios where multiple files define the same
    # module/class. Most users don't need this filter.
  end
end
