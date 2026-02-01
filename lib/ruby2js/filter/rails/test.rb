# Rails test filter - transforms minitest-style tests for dual-target execution
#
# This filter transforms Ruby minitest/spec-style tests so they can run:
# - In Rails via `bundle exec rake test` (unchanged, uses minitest)
# - In Juntos via `npm test` (transpiled to JS with async/await)
#
# It transforms:
# - describe/it blocks to async arrow functions
# - ActiveRecord operations to use await
# - before/after hooks
# - Generates appropriate imports for Juntos
#
# Usage:
#   # In test file
#   describe 'Article Model' do
#     it 'creates an article' do
#       article = Article.create(title: 'Test', body: 'Body content')
#       article.id.wont_be_nil
#     end
#   end

require 'ruby2js'
require_relative 'active_record'

module Ruby2JS
  module Filter
    module Rails
      module Test
        include SEXP

        def initialize(*args)
          # Note: super must be called first for JS class compatibility
          super
          @rails_test = nil
          @rails_test_models = []
          @rails_test_checked = false
          @rails_test_describe_depth = 0
        end

        # Handle describe/it/before/after blocks
        def on_block(node)
          # Only transform if we're in a test file
          return super unless is_test_file

          call = node.children.first
          return super unless call.type == :send && call.children.first.nil?

          method = call.children[1]

          case method
          when :describe, :context
            # describe 'something' do ... end
            # Track that we're inside describe for it/before/after detection
            # Note: Use explicit result variable for JS transpilation
            # (Ruby's implicit return from begin/ensure doesn't transpile well)
            result = nil
            begin
              @rails_test_describe_depth += 1
              # Collect model references from the body
              collect_test_model_references(node.children.last)
              # Process normally - describe blocks don't need async
              result = super
            ensure
              @rails_test_describe_depth -= 1
            end
            result

          when :it, :specify, :test
            return super unless @rails_test_describe_depth > 0
            # it 'does something' do ... end -> it('...', async () => { ... })
            args = call.children[2..-1]
            body = node.children.last

            # Collect models and wrap AR operations
            collect_test_model_references(body)
            wrapped_body = wrap_ar_operations(body)

            # Process the wrapped body
            processed_body = process(wrapped_body)

            # Create async arrow function block
            # The :async type with nil target creates: async () => { ... }
            async_fn = s(:async, nil, s(:args), processed_body)

            # Build: it('name', async () => { ... })
            s(:send, nil, method == :specify ? :test : method, *process_all(args), async_fn)

          when :before
            return super unless @rails_test_describe_depth > 0
            # before { ... } or before(:each) { ... } -> beforeEach(async () => { ... })
            scope_arg = call.children[2]
            hook_name = if scope_arg&.type == :sym && scope_arg.children.first == :all
              :beforeAll
            else
              :beforeEach
            end

            body = node.children.last
            collect_test_model_references(body)
            wrapped_body = wrap_ar_operations(body)
            processed_body = process(wrapped_body)

            async_fn = s(:async, nil, s(:args), processed_body)
            s(:send, nil, hook_name, async_fn)

          when :after
            return super unless @rails_test_describe_depth > 0
            # after { ... } or after(:each) { ... } -> afterEach(async () => { ... })
            scope_arg = call.children[2]
            hook_name = if scope_arg&.type == :sym && scope_arg.children.first == :all
              :afterAll
            else
              :afterEach
            end

            body = node.children.last
            collect_test_model_references(body)
            wrapped_body = wrap_ar_operations(body)
            processed_body = process(wrapped_body)

            async_fn = s(:async, nil, s(:args), processed_body)
            s(:send, nil, hook_name, async_fn)

          else
            super
          end
        end

        private

        # Check if we're processing a test file
        def is_test_file
          file = @options[:file]
          return false unless file
          file_str = file.to_s
          file_str.end_with?('_test.rb') ||
            file_str.end_with?('.test.rb') ||
            file_str.include?('/test/') ||
            file_str.include?('/spec/')
        end

        # Collect model references from test code
        def collect_test_model_references(node, visited = nil)
          visited = [] if visited.nil?
          return unless node.respond_to?(:type) && node.respond_to?(:children)
          return if visited.include?(node)
          visited.push(node)

          case node.type
          when :const
            # Check for top-level constant (potential model)
            if node.children[0].nil?
              name = node.children[1].to_s
              # Heuristic: capitalized, looks like a model name
              # Exclude common non-model constants
              excluded = %w[Test Minitest Vitest RSpec]
              if name =~ /\A[A-Z][a-z]/ && !excluded.include?(name)
                @rails_test_models << name unless @rails_test_models.include?(name)
              end
            end
          end

          # Recurse into children
          node.children.each do |child|
            collect_test_model_references(child, visited) if child.respond_to?(:type)
          end
        end

        # Wrap AR operations with await - delegates to shared helper
        def wrap_ar_operations(node)
          ActiveRecordHelpers.wrap_ar_operations(node, @rails_test_models)
        end
      end
    end

    DEFAULTS.push Rails::Test
  end
end
