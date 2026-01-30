require 'ruby2js'
require_relative 'active_record'

module Ruby2JS
  module Filter
    module Rails
      module Seeds
        include SEXP

        def initialize(*args)
          # Note: super must be called first for JS class compatibility
          super
          @rails_seeds = nil
          @rails_seeds_models = []
          @rails_seeds_checked = false
        end

        # Process top-level to wrap bare code in module Seeds if needed
        def process(node)
          # Skip if already checked or if on_module is processing
          return super if @rails_seeds_checked || @rails_seeds

          # Only wrap if this looks like a seeds file
          return super unless is_seeds_file

          # Handle nil node (comment-only input) - wrap in empty Seeds module
          if node.nil?
            @rails_seeds_checked = true
            wrapped = wrap_in_seeds_module(nil)
            return super(wrapped)
          end

          # Check if we need to wrap the code
          if needs_seeds_wrapper?(node)
            @rails_seeds_checked = true
            wrapped = wrap_in_seeds_module(node)
            return super(wrapped)
          end

          super
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

        # Check if we're processing a seeds file
        def is_seeds_file
          file = @options[:file]
          return false unless file
          file.to_s.end_with?('seeds.rb') || file.to_s.include?('/seeds/')
        end

        # Check if code needs to be wrapped in module Seeds
        def needs_seeds_wrapper?(node)
          return false unless node.respond_to?(:type)

          # Get top-level statements
          children = node.type == :begin ? node.children : [node]

          # Check if there's already a module Seeds (directly or inside export)
          has_seeds = children.any? do |child|
            next false unless child.respond_to?(:type)

            # Direct module Seeds
            if child.type == :module &&
               child.children[0]&.type == :const &&
               child.children[0].children[1] == :Seeds
              next true
            end

            # Module Seeds inside export
            if child.type == :export
              inner = child.children[0]
              if inner&.type == :module &&
                 inner.children[0]&.type == :const &&
                 inner.children[0].children[1] == :Seeds
                next true
              end
            end

            false
          end

          !has_seeds
        end

        # Wrap code in module Seeds { def self.run ... end }
        def wrap_in_seeds_module(node)
          # Handle nil node (empty/comment-only input)
          if node.nil?
            run_method = s(:defs, s(:self), :run, s(:args), nil)
            return s(:module, s(:const, nil, :Seeds), run_method)
          end

          # Get statements to wrap
          children = node.type == :begin ? node.children : [node]

          # Filter out nil children and non-executable nodes
          executable = children.select { |c| c.respond_to?(:type) }

          # Build the run method body
          run_body = if executable.empty?
            nil
          elsif executable.length == 1
            executable.first
          else
            s(:begin, *executable)
          end

          # Build: module Seeds; def self.run; ...; end; end
          run_method = s(:defs, s(:self), :run, s(:args), run_body)
          s(:module, s(:const, nil, :Seeds), run_method)
        end

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
            statements << s(:import, '../app/models/index.js', model_consts)
          end

          # Transform the module to make run async and wrap AR operations with await
          transformed_module = transform_seeds_module(module_node)

          # Add the export module Seeds (let ESM filter handle the rest)
          statements << s(:export, transformed_module)

          begin_node = s(:begin, *statements)
          result = process(begin_node)
          # Set empty comments on processed begin node to prevent first-location lookup
          # from incorrectly inheriting comments from child nodes
          @comments.set(result, [])
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

        # Wrap AR operations with await - delegates to shared helper
        def wrap_ar_operations(node)
          ActiveRecordHelpers.wrap_ar_operations(node, @rails_seeds_models)
        end
      end
    end

    DEFAULTS.push Rails::Seeds
  end
end
