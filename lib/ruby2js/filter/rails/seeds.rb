require 'ruby2js'

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

          # Add the export module Seeds (let ESM filter handle the rest)
          statements << s(:export, module_node)

          process(s(:begin, *statements))
        end
      end
    end

    DEFAULTS.push Rails::Seeds
  end
end
