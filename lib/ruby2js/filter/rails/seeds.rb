require 'ruby2js'

module Ruby2JS
  module Filter
    module Rails
      module Seeds
        include SEXP

        # ActiveRecord class methods that should be awaited
        AR_CLASS_METHODS = %i[all find find_by where first last count create create!].freeze

        def initialize(*args)
          # Note: super must be called first for JS class compatibility
          super
          @rails_seeds = nil
          @rails_seeds_models = []
        end

        # Detect module Seeds with def self.run
        def on_module(node)
          name, body = node.children

          # Skip if already processing (prevent infinite recursion)
          return super if @rails_seeds

          # Check for module Seeds
          return super unless name.type == :const && name.children[1] == :Seeds

          # Look for def self.run in the body
          return super unless has_self_run_method?(body)

          @rails_seeds = true
          @rails_seeds_models = []

          # Collect model references from the body
          collect_seeds_model_references(body)

          # Build the transformed output
          result = build_seeds_output(node)

          @rails_seeds = nil
          @rails_seeds_models = []

          result
        end

        private

        def has_self_run_method?(body)
          return false unless body

          children = body.type == :begin ? body.children : [body]
          children.any? do |child|
            child&.type == :defs &&
              child.children[0]&.type == :self &&
              child.children[1] == :run
          end
        end

        def collect_seeds_model_references(node, visited = nil)
          # Note: use Array for tracking visited nodes (object_id doesn't exist in JS,
          # and Set.include? becomes .includes() which doesn't exist on JS Set)
          visited = [] if visited.nil?
          return unless node.respond_to?(:type) && node.respond_to?(:children)
          return if visited.include?(node)
          visited.push(node)

          case node.type
          when :const
            # Check for top-level constant (potential model)
            if node.children[0].nil?
              name = node.children[1].to_s
              # Heuristic: capitalized, not Seeds itself, looks like a model name
              if name =~ /\A[A-Z][a-z]/ && name != 'Seeds'
                @rails_seeds_models << name unless @rails_seeds_models.include?(name)
              end
            end
          end

          # Recurse into children
          node.children.each do |child|
            collect_seeds_model_references(child, visited) if child.respond_to?(:type)
          end
        end

        def build_seeds_output(module_node)
          statements = []

          # Generate import for models if any were found
          if @rails_seeds_models.any?
            model_consts = @rails_seeds_models.map { |m| s(:const, nil, m.to_sym) }
            statements << s(:import, '../models/index.js', model_consts)
          end

          # Transform the module to make run async and wrap AR operations with await
          transformed_module = transform_seeds_module(module_node)

          # Add the export module Seeds (let ESM filter handle the rest)
          statements << s(:export, transformed_module)

          begin_node = s(:begin, *statements)
          result = process(begin_node)
          # Set empty comments on processed begin node to prevent first-location lookup
          # from incorrectly inheriting comments from child nodes
          if @comments.respond_to?(:set)
            @comments.set(result, [])
          else
            @comments[result] = []
          end
          result
        end

        def transform_seeds_module(module_node)
          name, body = module_node.children
          return module_node unless body

          children = body.type == :begin ? body.children : [body]
          transformed_children = children.map do |child|
            if child&.type == :defs &&
               child.children[0]&.type == :self &&
               child.children[1] == :run
              # Transform def self.run to async function with await wrappers
              transform_run_method(child)
            else
              child
            end
          end

          new_body = transformed_children.length == 1 ? transformed_children.first : s(:begin, *transformed_children)
          module_node.updated(nil, [name, new_body])
        end

        def transform_run_method(node)
          # node is: s(:defs, s(:self), :run, s(:args), body)
          _self_node, method_name, args, body = node.children

          # Transform body to wrap AR operations with await
          transformed_body = wrap_ar_operations(body)

          # Return async singleton method
          s(:asyncs, s(:self), method_name, args, transformed_body)
        end

        def wrap_ar_operations(node)
          return node unless node.respond_to?(:type)

          case node.type
          when :send
            target, method, *args = node.children

            # Check for class method calls on model constants (e.g., Article.create)
            if target&.type == :const && target.children[0].nil?
              const_name = target.children[1].to_s
              if @rails_seeds_models.include?(const_name) && AR_CLASS_METHODS.include?(method)
                # Wrap with await, process children first
                new_args = args.map { |a| wrap_ar_operations(a) }
                new_node = node.updated(nil, [target, method, *new_args])
                return new_node.updated(:await)
              end
            end

            # Process children recursively
            new_children = node.children.map do |c|
              c.respond_to?(:type) ? wrap_ar_operations(c) : c
            end
            # Note: explicit return for JS switch/case compatibility
            return node.updated(nil, new_children)

          else
            if node.children.any?
              # Note: use different variable name to avoid JS TDZ error in switch/case
              mapped_children = node.children.map do |c|
                c.respond_to?(:type) ? wrap_ar_operations(c) : c
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

    DEFAULTS.push Rails::Seeds
  end
end
