# Shared ActiveRecord support for Rails filters
#
# This module provides centralized definitions of ActiveRecord methods
# that need async/await handling when transpiled to JavaScript.
# Used by controller, seeds, and test filters.
#
# For selfhost compatibility, constants are inside the module (not parent)
# so they transpile as static class properties.

require 'ruby2js'

module Ruby2JS
  module Filter
    module Rails
      # Shared ActiveRecord helper methods
      # Constants and methods are inside this module for selfhost compatibility.
      module ActiveRecordHelpers
        extend SEXP

        # Class methods that return promises (need await)
        # These are called on model classes: Article.find, User.where, etc.
        # NOTE: Only include "terminal" methods that execute the query.
        # Chainable methods (includes, joins, limit, offset) are handled via
        # chain detection - only the final method in a chain gets awaited.
        AR_CLASS_METHODS = %i[
          all find find_by find_by! where not or and
          first last take sole
          count sum average minimum maximum
          create create!
          find_or_create_by find_or_create_by!
          find_or_initialize_by
          order
          distinct pluck pick ids exists?
          find_each find_in_batches
          update_all destroy_all delete_all
        ].freeze

        # Instance methods that return promises (need await)
        # These are called on model instances: article.save, user.destroy, etc.
        AR_INSTANCE_METHODS = %i[
          save save! update update! destroy destroy!
          reload touch
          valid? invalid?
        ].freeze

        # Association methods that return promises
        # These are called on associations: article.comments.create, etc.
        AR_ASSOCIATION_METHODS = %i[
          find create create! build
          count size length
          first last take
          where order limit
          exists? empty? any? none?
          pluck ids
          destroy_all delete_all
        ].freeze

        SEND_TYPES = [:send, :send!, :await!].freeze

        VARIABLE_TYPES = [:lvar, :ivar, :attr].freeze

        TEST_MACROS = %i[
          describe context it test specify setup teardown
          before after assert_raises assert_raise
          assert_difference assert_no_difference
        ].freeze

        LOOP_METHODS = %i[
          each each_with_index each_pair each_key
          each_value each_with_object
        ].freeze

        # --- Helper methods to reduce repetition ---

        # Extract model constant name if target is an unscoped constant (e.g., Article)
        # Returns the name string, or nil if not a bare constant.
        def self.model_const_name(target)
          return nil unless target&.type == :const && target.children[0].nil?
          target.children[1].to_s
        end

        # Check if a constant name is in the set of known model references
        def self.model_ref?(const_name, model_refs)
          return false unless const_name
          model_refs_array = model_refs ? [*model_refs] : []
          model_refs_array.include?(const_name)
        end

        # Walk a method chain to find the root receiver (past :send, :send!, :await!)
        def self.chain_root(node)
          current = node
          while current && SEND_TYPES.include?(current.type)
            current = current.children[0]
          end
          current
        end

        # Check if a method is a known scope on a given model
        def self.known_scope?(method, const_name, metadata)
          return false unless metadata
          models = metadata['models']
          return false unless models
          model_meta = models[const_name]
          return false unless model_meta
          scopes = model_meta['scopes'] || []
          scopes.include?(method.to_s)
        end

        # Check if a method is a custom async instance method defined on any model
        def self.custom_instance_method?(method, metadata)
          return false unless metadata
          # Use keys.each pattern for JS object compatibility
          metadata.keys.each do |_name|
            meta = metadata[_name]
            methods = meta['instance_methods']
            return true if methods && methods.include?(method.to_s)
          end
          false
        end

        # Check if target is a variable-like node (lvar, ivar, attr)
        def self.variable_target?(target)
          target && VARIABLE_TYPES.include?(target.type)
        end

        # Strip inner :await! nodes from a chain that will be wrapped with an outer await.
        # When the controller filter processes bottom-up, inner AR calls (e.g., where())
        # get wrapped with await! before chain detection fires for the terminal method.
        # Since Relation is thenable, awaiting an intermediate Relation resolves it to
        # an Array, breaking chainable methods like .or(). This method unwraps those
        # inner awaits so only the outermost call is awaited.
        def self.strip_inner_awaits(node)
          return node unless node.respond_to?(:type)

          if node.type == :await!
            # Unwrap: change type to :send! (forces parens) instead of :send.
            # AR methods like where() need parens even when zero-arg; plain :send
            # would produce property access (e.g., Heat.where instead of Heat.where()).
            return self.strip_inner_awaits(node.updated(:send!))
          end

          new_children = node.children.map do |c|
            c.respond_to?(:type) ? self.strip_inner_awaits(c) : c
          end
          node.updated(nil, new_children)
        end

        # Determine the await type for a :send node, without recursion.
        # Returns :await!, :await_attr, or nil.
        # Used by both wrap_with_await_if_needed (controller) and wrap_ar_operations (seeds/test).
        def self.classify_send(node, model_refs, metadata=nil)
          target, method, *args = node.children

          # 1. Model.class_method (e.g., Article.find, User.where)
          const_name = self.model_const_name(target)
          if self.model_ref?(const_name, model_refs)
            return :await! if AR_CLASS_METHODS.include?(method)

            # Zero-arg: scope (getter) or custom class method (parens)
            if args.empty?
              return self.known_scope?(method, const_name, metadata) ? :await_attr : :await!
            end
          end

          # 2. Chained call ending with AR class method (e.g., Article.includes(:x).all)
          if target && SEND_TYPES.include?(target.type) && AR_CLASS_METHODS.include?(method)
            root = self.chain_root(target)
            root_name = self.model_const_name(root)
            return :await! if self.model_ref?(root_name, model_refs)
          end

          # 3. Scope chained after an awaited call (e.g., Article.where(...).by_name)
          if target&.type == :await!
            root = self.chain_root(target)
            root_name = self.model_const_name(root)
            if self.model_ref?(root_name, model_refs) && self.known_scope?(method, root_name, metadata)
              return :await_attr
            end
          end

          # 4. Instance method on variable (e.g., article.save, @article.update)
          if self.variable_target?(target)
            return :await! if AR_INSTANCE_METHODS.include?(method)

            # Custom async instance method (e.g., @studio.pairs)
            models = metadata ? metadata['models'] : nil
            models = metadata if metadata && !models  # wrap_ar_operations passes model_metadata directly
            return :await! if models && self.custom_instance_method?(method, models)
          end

          # 5. Association chain (e.g., article.comments.create!)
          if target&.type == :send && AR_ASSOCIATION_METHODS.include?(method)
            assoc_target, assoc_method = target.children
            # Must start from variable, not [] (hash/array access)
            if (self.variable_target?(assoc_target) || assoc_target&.type == :self) && assoc_method != :[]
              return :await!
            end
          end

          nil
        end

        # Wrap ActiveRecord operations with await for async database support
        # Takes the node to potentially wrap and an array of known model names
        # Optional metadata hash contains model info (scopes, associations, etc.)
        # Used by controller filter (single-node, non-recursive).
        def self.wrap_with_await_if_needed(node, model_refs, metadata=nil)
          return node unless node.respond_to?(:type) && node.type == :send

          await_type = self.classify_send(node, model_refs, metadata)
          return node unless await_type

          if SEND_TYPES.include?(node.children[0]&.type)
            # Chain: strip inner awaits before wrapping
            stripped = self.strip_inner_awaits(node)
            return stripped.updated(await_type)
          end

          node.updated(await_type)
        end

        # Recursively wrap AR operations in an AST node
        # Used by seeds and test filters for transforming method bodies
        # model_metadata: optional hash of { ModelName => { 'instance_methods' => [...] } }
        #   for detecting custom instance methods that need await+parens in chains
        def self.wrap_ar_operations(node, model_refs, model_metadata=nil)
          return node unless node.respond_to?(:type)

          case node.type
          when :send
            target, method, *args = node.children

            # Check for chained AR instance methods (e.g., card.reload.status)
            # When an AR instance method like .reload appears as the receiver of
            # another send, wrap it with await: (await card.reload()).status
            if target&.type == :send
              chain_receiver = target.children[0]
              chain_method = target.children[1]
              if self.variable_target?(chain_receiver) && AR_INSTANCE_METHODS.include?(chain_method)
                wrapped_target = target.updated(:await!)
                new_args = args.map { |a| self.wrap_ar_operations(a, model_refs, model_metadata) }
                return node.updated(nil, [wrapped_target, method, *new_args])
              end
            end

            # Check for association chain with custom intermediate method
            if target&.type == :send && AR_ASSOCIATION_METHODS.include?(method)
              assoc_target = target.children[0]
              assoc_method = target.children[1]
              if self.variable_target?(assoc_target) && assoc_method != :[] &&
                 model_metadata && self.custom_instance_method?(assoc_method, model_metadata)
                wrapped_target = target.updated(:await!)
                new_args = args.map { |a| self.wrap_ar_operations(a, model_refs, model_metadata) }
                new_node = node.updated(nil, [wrapped_target, method, *new_args])
                return new_node.updated(:await!)
              end
            end

            await_type = self.classify_send(node, model_refs, model_metadata)
            if await_type
              new_args = args.map { |a| self.wrap_ar_operations(a, model_refs, model_metadata) }
              new_node = node.updated(nil, [target, method, *new_args])
              return new_node.updated(await_type)
            end

            # Process children recursively
            new_children = node.children.map do |c|
              c.respond_to?(:type) ? self.wrap_ar_operations(c, model_refs, model_metadata) : c
            end
            return node.updated(nil, new_children)

          when :lvasgn, :ivasgn
            var_name, value = node.children
            if value.respond_to?(:type)
              new_value = self.wrap_ar_operations(value, model_refs, model_metadata)
              return node.updated(nil, [var_name, new_value])
            end
            return node

          when :block
            call_node, args_node, body_node = node.children
            new_call = call_node.respond_to?(:type) ? self.wrap_ar_operations(call_node, model_refs, model_metadata) : call_node
            new_body = body_node.respond_to?(:type) ? self.wrap_ar_operations(body_node, model_refs, model_metadata) : body_node

            call_method = call_node.type == :send ? call_node.children[1] : nil

            if !TEST_MACROS.include?(call_method) &&
               !LOOP_METHODS.include?(call_method) &&
               self.contains_await?(new_body)
              async_fn = new_body.updated(:async, [nil, args_node, new_body])
              return node.updated(new_call.type, [*new_call.children, async_fn])
            end

            return node.updated(nil, [new_call, args_node, new_body])

          else
            if node.children.any?
              mapped_children = node.children.map do |c|
                c.respond_to?(:type) ? self.wrap_ar_operations(c, model_refs, model_metadata) : c
              end
              return node.updated(nil, mapped_children)
            else
              return node
            end
          end
        end

        # Check if an AST node contains :await, :await!, or :await_attr nodes.
        # Does not recurse into :async nodes (already handled).
        def self.contains_await?(node)
          return false unless node.respond_to?(:type)
          return true if node.type == :await || node.type == :await! || node.type == :await_attr
          return false if node.type == :async
          node.children.any? { |c| c.respond_to?(:type) && self.contains_await?(c) }
        end
      end
    end
  end
end
