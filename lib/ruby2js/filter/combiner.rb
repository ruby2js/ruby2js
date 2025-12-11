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
            result.concat(flatten_begins(node.children))
          else
            result << node
          end
        end
        result
      end

      # Merge duplicate module and class definitions
      def merge_definitions(nodes)
        # Flatten any nested :begin nodes first
        nodes = flatten_begins(nodes)

        # Track definitions by their full name (including nesting)
        definitions = {}  # name => [index, node]
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
        if original.type == :class
          # class has 3 children: name, superclass, body
          orig_name, orig_super, orig_body = original.children
          reopen_name, reopen_super, reopen_body = reopened.children
          superclass = orig_super || reopen_super
        else
          # module has 2 children: name, body
          orig_name, orig_body = original.children
          reopen_name, reopen_body = reopened.children
          superclass = nil
        end

        # Merge bodies
        orig_children = body_children(orig_body)
        reopen_children = body_children(reopen_body)

        # Recursively merge any nested modules/classes
        merged_children = merge_definitions(orig_children + reopen_children)

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
        return body.children.to_a if body.type == :begin
        [body]
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
        cvasgns + others
      end
    end

    # NOTE: Combiner is NOT added to DEFAULTS because it's specifically
    # for self-hosting scenarios where multiple files define the same
    # module/class. Most users don't need this filter.
  end
end
