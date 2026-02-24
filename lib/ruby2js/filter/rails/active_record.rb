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
          all find find_by find_by! where
          first last take
          count sum average minimum maximum
          create create!
          find_or_create_by find_or_create_by!
          find_or_initialize_by
          order
          distinct pluck ids exists?
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

        # Strip inner :await! nodes from a chain that will be wrapped with an outer await.
        # When the controller filter processes bottom-up, inner AR calls (e.g., where())
        # get wrapped with await! before chain detection fires for the terminal method.
        # Since Relation is thenable, awaiting an intermediate Relation resolves it to
        # an Array, breaking chainable methods like .or(). This method unwraps those
        # inner awaits so only the outermost call is awaited.
        def self.strip_inner_awaits(node)
          return node unless node.respond_to?(:type)

          if node.type == :await!
            # Unwrap: change type back to :send, recurse on children
            return self.strip_inner_awaits(node.updated(:send))
          end

          new_children = node.children.map do |c|
            c.respond_to?(:type) ? self.strip_inner_awaits(c) : c
          end
          node.updated(nil, new_children)
        end

        # Wrap ActiveRecord operations with await for async database support
        # Takes the node to potentially wrap and an array of known model names
        def self.wrap_with_await_if_needed(node, model_refs)
          return node unless node.respond_to?(:type) && node.type == :send

          target, method, *_args = node.children

          # Check for class method calls on model constants (e.g., Article.find)
          if target&.type == :const && target.children[0].nil?
            const_name = target.children[1].to_s
            # Convert Set to Array for JS compatibility (Set.include? doesn't exist in JS)
            model_refs_array = model_refs ? [*model_refs] : []
            if model_refs_array.include?(const_name) && AR_CLASS_METHODS.include?(method)
              # Use updated(:await!) to force parens (method call, not property access)
              return node.updated(:await!)
            end
          end

          # Check for chained method calls ending with an AR class method
          # e.g., Article.includes(:comments).all, Article.where(...).first
          # Also handle chains where inner nodes are already await-wrapped
          if (target&.type == :send || target&.type == :await!) && AR_CLASS_METHODS.include?(method)
            # Walk up the chain to find the root target
            chain_start = target
            while chain_start&.type == :send || chain_start&.type == :await!
              # :await! wraps a single child node
              if chain_start.type == :await!
                chain_start = chain_start.children[0]
              else
                chain_start = chain_start.children[0]
              end
            end
            # If chain starts with a model constant, await the whole thing
            # Strip inner awaits first — intermediate Relation calls (where, order, etc.)
            # must not be individually awaited or they resolve to Arrays.
            if chain_start&.type == :const && chain_start.children[0].nil?
              const_name = chain_start.children[1].to_s
              model_refs_array = model_refs ? [*model_refs] : []
              if model_refs_array.include?(const_name)
                stripped = self.strip_inner_awaits(node)
                return stripped.updated(:await!)
              end
            end
          end

          # Check for instance method calls on local variables (e.g., article.save)
          if target&.type == :lvar && AR_INSTANCE_METHODS.include?(method)
            return node.updated(:await!)
          end

          # Check for instance method calls on instance variables (e.g., @article.save)
          if target&.type == :ivar && AR_INSTANCE_METHODS.include?(method)
            return node.updated(:await!)
          end

          # Check for association method chains (e.g., article.comments.find(id), article.comments.count)
          # These are: lvar.accessor.method where method is an AR association method
          if target&.type == :send && AR_ASSOCIATION_METHODS.include?(method)
            assoc_target, assoc_method = target.children
            # If the chain starts from a local variable or instance variable,
            # and the intermediate method is a named accessor (not [] subscript,
            # which is hash/array access, not an association proxy)
            if (assoc_target&.type == :lvar || assoc_target&.type == :ivar || assoc_target&.type == :self || assoc_target&.type == :attr) &&
               assoc_method != :[]
              return node.updated(:await!)
            end
          end

          node
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

            # Check for class method calls on model constants (e.g., Article.create)
            if target&.type == :const && target.children[0].nil?
              const_name = target.children[1].to_s
              model_refs_array = model_refs ? [*model_refs] : []
              if model_refs_array.include?(const_name)
                if AR_CLASS_METHODS.include?(method)
                  # Known AR class method: wrap with await!
                  new_args = args.map { |a| self.wrap_ar_operations(a, model_refs, model_metadata) }
                  new_node = node.updated(nil, [target, method, *new_args])
                  return new_node.updated(:await!)
                elsif args.empty?
                  # Zero-arg call on model constant (e.g., Card.closed scope getter)
                  # Scopes return Relations that need await, use await_attr
                  # to preserve property access (no parens for static getters)
                  return node.updated(:await_attr)
                end
              end
            end

            # Check for instance method calls (e.g., article.save, @article.update)
            # Also handles :attr targets for fixture refs (_fixtures.card)
            if (target&.type == :lvar || target&.type == :ivar || target&.type == :attr) && AR_INSTANCE_METHODS.include?(method)
              new_args = args.map { |a| self.wrap_ar_operations(a, model_refs, model_metadata) }
              new_node = node.updated(nil, [target, method, *new_args])
              return new_node.updated(:await!)
            end

            # Check for chained AR instance methods (e.g., card.reload.status)
            # When an AR instance method like .reload appears as the receiver of
            # another send, wrap it with await: (await card.reload()).status
            if target&.type == :send
              chain_receiver = target.children[0]
              chain_method = target.children[1]
              if (chain_receiver&.type == :lvar || chain_receiver&.type == :ivar || chain_receiver&.type == :attr) &&
                 AR_INSTANCE_METHODS.include?(chain_method)
                wrapped_target = target.updated(:await!)
                new_args = args.map { |a| self.wrap_ar_operations(a, model_refs, model_metadata) }
                return node.updated(nil, [wrapped_target, method, *new_args])
              end
            end

            # Check for association methods (e.g., article.comments.create!, workflow.nodes.count)
            # Must be a chain: lvar.accessor.method (not just lvar.find which could be Array#find)
            # Note: :attr (fixture refs like _fixtures.card) intentionally excluded here.
            # Fixture association chains go through the functions filter (.last -> .at(-1))
            # and assert_difference wraps count calls explicitly.
            if target&.type == :send && AR_ASSOCIATION_METHODS.include?(method)
              assoc_target = target.children[0]
              assoc_method = target.children[1]
              # Only wrap if chain starts from lvar/ivar/attr and accessor isn't [] (hash/array access)
              if (assoc_target&.type == :lvar || assoc_target&.type == :ivar || assoc_target&.type == :attr) && assoc_method != :[]
                # Check if the intermediate method is a custom instance method (not an association getter).
                # Custom methods are async and need await+parens; association getters are sync.
                is_custom_method = false
                if model_metadata
                  model_metadata.each do |_name, meta| # Pragma: entries
                    methods = meta['instance_methods']
                    if methods && methods.include?(assoc_method.to_s)
                      is_custom_method = true
                    end
                  end
                end

                if is_custom_method
                  # Custom async method: await the intermediate call, then await the outer
                  wrapped_target = target.updated(:await!)
                  new_args = args.map { |a| self.wrap_ar_operations(a, model_refs, model_metadata) }
                  new_node = node.updated(nil, [wrapped_target, method, *new_args])
                  return new_node.updated(:await!)
                end

                # Wrap with await, process target and args
                new_target = self.wrap_ar_operations(target, model_refs, model_metadata)
                new_args = args.map { |a| self.wrap_ar_operations(a, model_refs, model_metadata) }
                new_node = node.updated(nil, [new_target, method, *new_args])
                return new_node.updated(:await!)
              end
            end

            # Process children recursively
            new_children = node.children.map do |c|
              c.respond_to?(:type) ? self.wrap_ar_operations(c, model_refs, model_metadata) : c
            end
            # Note: explicit return for JS switch/case compatibility
            return node.updated(nil, new_children)

          when :lvasgn, :ivasgn
            # Variable assignment - wrap the value if it's an AR operation
            var_name, value = node.children
            if value.respond_to?(:type)
              new_value = self.wrap_ar_operations(value, model_refs, model_metadata)
              return node.updated(nil, [var_name, new_value])
            end
            return node

          when :block
            # Block node: s(:block, call, args, body)
            # Process body recursively, then check if it contains await.
            # If so, convert the block to pass an async arrow function,
            # since `await` is only valid inside `async` functions.
            # Only convert blocks for method calls with receivers (e.g., array.map { })
            # or lambdas. Don't convert blocks for assertion macros (assert_raises, etc.)
            # which are handled by the test filter's on_block.
            call_node, args_node, body_node = node.children
            new_call = call_node.respond_to?(:type) ? self.wrap_ar_operations(call_node, model_refs, model_metadata) : call_node
            new_body = body_node.respond_to?(:type) ? self.wrap_ar_operations(body_node, model_refs, model_metadata) : body_node

            # Exclude blocks handled by test filter's on_block (they add async themselves)
            test_macros = [:describe, :context, :it, :test, :specify, :setup, :teardown,
                          :before, :after, :assert_raises, :assert_raise,
                          :assert_difference, :assert_no_difference]
            call_method = call_node.type == :send ? call_node.children[1] : nil
            is_test_macro = call_method && test_macros.include?(call_method)

            if !is_test_macro && self.contains_await?(new_body)
              # Convert: s(:block, call, args, body) → s(call.type, *call.children, s(:async, nil, args, body))
              async_fn = new_body.updated(:async, [nil, args_node, new_body])
              return node.updated(new_call.type, [*new_call.children, async_fn])
            end

            return node.updated(nil, [new_call, args_node, new_body])

          else
            if node.children.any?
              # Note: use different variable name to avoid JS TDZ error in switch/case
              mapped_children = node.children.map do |c|
                c.respond_to?(:type) ? self.wrap_ar_operations(c, model_refs, model_metadata) : c
              end
              # Note: explicit return for JS switch/case compatibility
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
