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
          if target&.type == :send && AR_CLASS_METHODS.include?(method)
            # Walk up the chain to find the root target
            chain_start = target
            while chain_start&.type == :send
              chain_start = chain_start.children[0]
            end
            # If chain starts with a model constant, await the whole thing
            if chain_start&.type == :const && chain_start.children[0].nil?
              const_name = chain_start.children[1].to_s
              model_refs_array = model_refs ? [*model_refs] : []
              if model_refs_array.include?(const_name)
                return node.updated(:await!)
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
            if (assoc_target&.type == :lvar || assoc_target&.type == :ivar) &&
               assoc_method != :[]
              return node.updated(:await!)
            end
          end

          node
        end

        # Recursively wrap AR operations in an AST node
        # Used by seeds and test filters for transforming method bodies
        def self.wrap_ar_operations(node, model_refs)
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
                  new_args = args.map { |a| self.wrap_ar_operations(a, model_refs) }
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
            if (target&.type == :lvar || target&.type == :ivar) && AR_INSTANCE_METHODS.include?(method)
              new_args = args.map { |a| self.wrap_ar_operations(a, model_refs) }
              new_node = node.updated(nil, [target, method, *new_args])
              return new_node.updated(:await!)
            end

            # Check for chained AR instance methods (e.g., card.reload.status)
            # When an AR instance method like .reload appears as the receiver of
            # another send, wrap it with await: (await card.reload()).status
            if target&.type == :send
              chain_receiver = target.children[0]
              chain_method = target.children[1]
              if (chain_receiver&.type == :lvar || chain_receiver&.type == :ivar) &&
                 AR_INSTANCE_METHODS.include?(chain_method)
                wrapped_target = target.updated(:await!)
                new_args = args.map { |a| self.wrap_ar_operations(a, model_refs) }
                return node.updated(nil, [wrapped_target, method, *new_args])
              end
            end

            # Check for association methods (e.g., article.comments.create!, workflow.nodes.count)
            # Must be a chain: lvar.accessor.method (not just lvar.find which could be Array#find)
            if target&.type == :send && AR_ASSOCIATION_METHODS.include?(method)
              assoc_target = target.children[0]
              assoc_method = target.children[1]
              # Only wrap if chain starts from lvar/ivar and accessor isn't [] (hash/array access)
              if (assoc_target&.type == :lvar || assoc_target&.type == :ivar) && assoc_method != :[]
                # Wrap with await, process target and args
                new_target = self.wrap_ar_operations(target, model_refs)
                new_args = args.map { |a| self.wrap_ar_operations(a, model_refs) }
                new_node = node.updated(nil, [new_target, method, *new_args])
                return new_node.updated(:await!)
              end
            end

            # Process children recursively
            new_children = node.children.map do |c|
              c.respond_to?(:type) ? self.wrap_ar_operations(c, model_refs) : c
            end
            # Note: explicit return for JS switch/case compatibility
            return node.updated(nil, new_children)

          when :lvasgn, :ivasgn
            # Variable assignment - wrap the value if it's an AR operation
            var_name, value = node.children
            if value.respond_to?(:type)
              new_value = self.wrap_ar_operations(value, model_refs)
              return node.updated(nil, [var_name, new_value])
            end
            return node

          else
            if node.children.any?
              # Note: use different variable name to avoid JS TDZ error in switch/case
              mapped_children = node.children.map do |c|
                c.respond_to?(:type) ? self.wrap_ar_operations(c, model_refs) : c
              end
              # Note: explicit return for JS switch/case compatibility
              return node.updated(nil, mapped_children)
            else
              return node
            end
          end
        end
      end
    end
  end
end
