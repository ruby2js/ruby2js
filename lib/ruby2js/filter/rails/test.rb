# Rails test filter - transforms minitest-style tests for dual-target execution
#
# This filter transforms Ruby minitest/spec-style and class-based tests so they
# can run:
# - In Rails via `bundle exec rake test` (unchanged, uses minitest)
# - In Juntos via `npm test` (transpiled to JS with async/await)
#
# It transforms:
# - describe/it blocks to async arrow functions
# - class FooTest < ActiveSupport::TestCase to describe blocks
# - setup/teardown to beforeEach/afterEach
# - ActiveRecord operations to use await
# - before/after hooks
# - Minitest assertions to vitest expect() calls
# - Fixture references: songs(:one) -> songs("one")
# - Strips require "test_helper"
#
# Controller/integration test transforms:
# - HTTP method calls (get, post, patch, delete) to controller action calls
# - URL helpers (_url) to path helpers (_path)
# - assert_response to expect() calls
# - assert_redirected_to to expect(response.redirect) calls
# - assert_difference/assert_no_difference blocks
# - Instance variables to local variables
# - Emits context() helper function
#
# Usage:
#   # Spec-style test
#   describe 'Article Model' do
#     it 'creates an article' do
#       article = Article.create(title: 'Test', body: 'Body content')
#       article.id.wont_be_nil
#     end
#   end
#
#   # Class-based test
#   class ArticleTest < ActiveSupport::TestCase
#     test "creates an article" do
#       article = Article.create(title: 'Test')
#       assert article.valid?
#     end
#   end
#
#   # Integration test
#   class ArticlesControllerTest < ActionDispatch::IntegrationTest
#     test "should get index" do
#       get articles_url
#       assert_response :success
#     end
#   end

require 'ruby2js'
require 'ruby2js/inflector'
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
          @rails_test_controllers = []
          @rails_test_path_helpers = []
          @rails_test_checked = false
          @rails_test_describe_depth = 0
          @rails_test_integration = false
          @rails_test_system = false
          @rails_test_class_controller = nil
          @rails_test_response_var = false
          @rails_test_current_handled = false
          @rails_test_assert_select_scope = nil
          @rails_test_has_assert_select = false
          @rails_test_stimulus_controllers = []
          @rails_test_has_stimulus = false
          @rails_test_has_system_test = false
        end

        # Handle class-based test definitions
        def on_class(node)
          return super unless is_test_file

          class_name, superclass, body = node.children

          # Check if this is a test class (ActiveSupport::TestCase, etc.)
          return super unless test_class?(superclass)

          # Strip "Test" suffix for describe name
          name = class_name.children.last.to_s
          describe_name = name.end_with?('Test') ? name[0..-5] : name

          # Detect integration and system test classes
          is_integration = integration_test_class?(superclass)
          is_system = system_test_class?(superclass)

          result = nil
          begin
            @rails_test_describe_depth += 1
            @rails_test_integration = is_system ? true : is_integration
            @rails_test_system = is_system
            @rails_test_class_controller = describe_name if is_integration && describe_name.end_with?('Controller')
            @rails_test_current_handled = false

            # Collect model references from the body and shared metadata
            collect_test_model_references(body) if body
            seed_models_from_metadata

            # Transform class body
            transformed_body = transform_class_body(body)

            # For integration tests (not system tests), prepend context helper
            if is_integration && !is_system && transformed_body
              context_helper = build_context_helper
              if transformed_body.type == :begin
                transformed_body = s(:begin, context_helper, *transformed_body.children)
              else
                transformed_body = s(:begin, context_helper, transformed_body)
              end
            end

            # Prepend fixture setup (let _fixtures = {} + beforeEach) to describe body
            fixture_nodes = build_fixture_nodes

            # Add standalone Current attributes beforeEach if no setup block handled it
            current_standalone = nil
            if !@rails_test_current_handled
              current_standalone = build_current_standalone_before_each
            end

            extra_nodes = fixture_nodes
            extra_nodes.push(current_standalone) if current_standalone

            if @rails_test_has_stimulus
              extra_nodes.push(s(:lvasgn, :_stimulusApp))
              extra_nodes.push(s(:jsraw,
                'afterEach(() => { if (_stimulusApp) {' \
                ' _stimulusApp.stop(); _stimulusApp = undefined }' \
                ' document.body.innerHTML = "" })'))
            end

            if is_system
              extra_nodes.push(s(:jsraw, 'afterEach(() => cleanup())'))
            end

            if extra_nodes.length > 0
              if transformed_body && transformed_body.type == :begin
                transformed_body = s(:begin, *extra_nodes, *transformed_body.children)
              elsif transformed_body
                transformed_body = s(:begin, *extra_nodes, transformed_body)
              else
                transformed_body = s(:begin, *extra_nodes)
              end
            end

            # Build: describe("Name", () => { ... })
            describe_block = s(:block,
              s(:send, nil, :describe, s(:str, describe_name)),
              s(:args),
              transformed_body)

            # Generate imports from metadata (models, controllers, path helpers)
            import_nodes = build_test_imports
            if import_nodes.length > 0
              result = s(:begin, *import_nodes, describe_block)
            else
              result = describe_block
            end
          ensure
            @rails_test_describe_depth -= 1
            @rails_test_integration = false
            @rails_test_system = false
          end
          result
        end

        # Strip require "test_helper" and handle controller-specific sends
        def on_send(node)
          return super unless is_test_file

          target, method, *args = node.children

          # Strip require "test_helper" and "application_system_test_case"
          if target.nil? && method == :require && args.length == 1 &&
             args.first.type == :str &&
             %w[test_helper application_system_test_case].include?(args.first.children.first)
            return s(:hide)
          end

          # Strip include SomeHelper (meaningless in ejected JS tests)
          if target.nil? && method == :include && args.length == 1 &&
             args.first.type == :const
            import_mode = @options[:metadata] && @options[:metadata]['import_mode']
            if import_mode == 'eject'
              return s(:hide)
            end
          end

          # Only transform assertions inside test describe blocks
          if @rails_test_describe_depth > 0
            # Integration test specific transforms
            if @rails_test_integration
              # System test (Capybara) transforms
              if @rails_test_system
                result = transform_system_test_method(target, method, args)
                return result if result
              else
                # HTTP method calls -> controller action calls
                if target.nil? && [:get, :post, :patch, :put, :delete].include?(method)
                  return transform_http_to_action(method, args)
                end

                # assert_response
                if target.nil? && method == :assert_response
                  return transform_assert_response(args)
                end

                # assert_redirected_to
                if target.nil? && method == :assert_redirected_to
                  return transform_assert_redirected_to(args)
                end

                # assert_select
                if target.nil? && method == :assert_select
                  return transform_assert_select(args)
                end

                # connect_stimulus "identifier", ControllerClass
                if target.nil? && method == :connect_stimulus && args.length == 2
                  return transform_connect_stimulus(args)
                end
              end

              # URL helper -> path helper (standalone, e.g. in assert_redirected_to context)
              if target.nil? && method.to_s.end_with?('_url') && ![:get, :post, :patch, :put, :delete].include?(method)
                return transform_url_to_path(method, args)
              end

              # Flash access: flash[:key] -> _flash.key
              if target&.type == :send &&
                 target.children[0].nil? && target.children[1] == :flash &&
                 method == :[] && args.length == 1 && args[0].type == :sym
                key = args[0].children[0]
                return s(:attr, s(:lvar, :_flash), key)
              end

              # Instance variables -> local variables
              # (handled via on_ivar/on_ivasgn below)
            end

            # skip -> return (for skip unless defined? Document)
            if target.nil? && method == :skip
              return s(:return)
            end

            # await_mutations -> await setTimeout promise
            if target.nil? && method == :await_mutations && args.empty?
              return s(:send, nil, :await,
                s(:send, s(:const, nil, :Promise), :new,
                  s(:block, s(:send, nil, :lambda), s(:args, s(:arg, :resolve)),
                    s(:send, nil, :setTimeout, s(:lvar, :resolve), s(:int, 0)))))
            end

            result = transform_assertion(target, method, args)
            return result if result

            # Fixture references: songs(:one) -> songs("one")
            result = transform_fixture_ref(target, method, args)
            return result if result
          end

          super
        end

        # Transform instance variable reads in test context
        # Converts @foo to foo (local variable) inside test blocks
        def on_ivar(node)
          if @rails_test_describe_depth > 0
            var_name = node.children.first.to_s.sub(/^@/, '')
            return s(:lvar, var_name.to_sym)
          end
          super
        end

        # Transform instance variable assignments in test context
        # Converts @foo = x to foo = x inside test blocks
        def on_ivasgn(node)
          if @rails_test_describe_depth > 0
            var_name = node.children.first.to_s.sub(/^@/, '')
            value = node.children[1]
            return s(:lvasgn, var_name.to_sym, process(value))
          end
          super
        end

        # Handle describe/it/before/after/setup/teardown blocks
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

          when :setup
            return super unless @rails_test_describe_depth > 0
            # setup do ... end -> beforeEach(async () => { ... })
            body = node.children.last
            collect_test_model_references(body)

            # Extract ivar names from setup body so they can be declared at
            # describe scope. This ensures variables like @article set in setup
            # are accessible in test functions (not block-scoped to beforeEach).
            ivar_names = extract_ivar_names(body)

            # Check if body has Current.xxx = ... assignments before processing
            has_current = has_current_assignments(body)

            wrapped_body = wrap_test_ar_operations(body)
            wrapped_body = ensure_statement_method_calls(wrapped_body)
            processed_body = process(wrapped_body)

            # Merge global Current attributes and add settle() if needed
            global_current = build_global_current_nodes
            if global_current.any? || has_current
              @rails_test_current_handled = true
              settle = s(:await!, s(:const, nil, :Current), :settle)
              if processed_body.respond_to?(:type) && processed_body.type == :begin
                processed_body = s(:begin, *global_current, *processed_body.children, settle)
              else
                processed_body = s(:begin, *global_current, processed_body, settle)
              end
            end

            async_fn = s(:async, nil, s(:args), processed_body)
            before_each = s(:send, nil, :beforeEach, async_fn)

            if ivar_names.any?
              # Emit: let var1; let var2; beforeEach(async () => { var1 = ...; var2 = ... })
              declarations = ivar_names.map { |name| s(:lvasgn, name) }
              s(:begin, *declarations, before_each)
            else
              before_each
            end

          when :teardown
            return super unless @rails_test_describe_depth > 0
            # teardown do ... end -> afterEach(async () => { ... })
            body = node.children.last
            collect_test_model_references(body)
            wrapped_body = wrap_test_ar_operations(body)
            wrapped_body = ensure_statement_method_calls(wrapped_body)
            processed_body = process(wrapped_body)

            async_fn = s(:async, nil, s(:args), processed_body)
            s(:send, nil, :afterEach, async_fn)

          when :assert_raises, :assert_raise
            return super unless @rails_test_describe_depth > 0
            # assert_raises(Error) do ... end -> expect(() => { ... }).toThrow(Error)
            error_args = call.children[2..-1]
            body = node.children.last
            processed_body = process(body)

            arrow_fn = s(:async, nil, s(:args), processed_body)

            if error_args.length > 0
              s(:send,
                s(:send, nil, :expect, arrow_fn),
                :toThrow, *process_all(error_args))
            else
              s(:send!,
                s(:send, nil, :expect, arrow_fn),
                :toThrow)
            end

          when :accept_confirm
            return super unless @rails_test_describe_depth > 0
            return super unless @rails_test_system
            # accept_confirm do ... end -> await acceptConfirm(async () => { ... })
            body = node.children.last
            wrapped_body = wrap_test_ar_operations(body)
            wrapped_body = ensure_statement_method_calls(wrapped_body)
            processed_body = process(wrapped_body)
            async_fn = s(:async, nil, s(:args), processed_body)
            s(:send, nil, :await, s(:send!, nil, :acceptConfirm, async_fn))

          when :assert_difference, :assert_no_difference
            return super unless @rails_test_describe_depth > 0
            transform_assert_difference(call, node.children.last, method == :assert_no_difference)

          when :assert_select
            return super unless @rails_test_describe_depth > 0
            return super unless @rails_test_integration
            transform_assert_select_block(call, node.children.last)

          when :it, :specify, :test
            return super unless @rails_test_describe_depth > 0
            # it 'does something' do ... end -> it('...', async () => { ... })
            args = call.children[2..-1]
            body = node.children.last

            # Collect models and wrap AR operations
            collect_test_model_references(body)
            wrapped_body = wrap_test_ar_operations(body)
            wrapped_body = ensure_statement_method_calls(wrapped_body)

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
            wrapped_body = wrap_test_ar_operations(body)
            wrapped_body = ensure_statement_method_calls(wrapped_body)
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
            wrapped_body = wrap_test_ar_operations(body)
            wrapped_body = ensure_statement_method_calls(wrapped_body)
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

        # Extract instance variable names from a setup body.
        # Returns an array of symbols like [:article, :comment].
        # Recurses into all compound nodes (begin, masgn, mlhs, etc.)
        # to find ivasgn nodes regardless of nesting depth.
        def extract_ivar_names(node)
          names = []
          return names unless node.respond_to?(:type)
          if node.type == :ivasgn
            names << node.children.first.to_s.sub(/^@/, '').to_sym
          end
          node.children.each do |child|
            if child.respond_to?(:type)
              extract_ivar_names(child).each { |n| names.push(n) }
            end
          end
          names.uniq
        end

        # Collect model references from test code
        def collect_test_model_references(node, visited = nil)
          visited = [] if visited.nil?
          return unless node.respond_to?(:type) && node.respond_to?(:children)
          return if visited.include?(node)
          visited.push(node)

          case node.type
          when :const
            # Check for top-level constant (potential model or controller)
            if node.children[0].nil?
              name = node.children[1].to_s
              # Heuristic: capitalized, looks like a model/controller name
              # Exclude common non-model constants
              excluded = %w[Test Minitest Vitest RSpec]
              if name =~ /\A[A-Z][a-z]/ && !excluded.include?(name)
                if name.end_with?('Controller')
                  @rails_test_controllers << name unless @rails_test_controllers.include?(name)
                else
                  @rails_test_models << name unless @rails_test_models.include?(name)
                end
              end
            end
          when :send
            # Track path helper calls: xxx_path(...)
            if node.children[0].nil?
              method_name = node.children[1].to_s
              if method_name.end_with?('_path')
                @rails_test_path_helpers << method_name unless @rails_test_path_helpers.include?(method_name)
              end
            end
          when :str
            # Extract model references from assert_difference string args
            # e.g., "Comment.count" -> Comment
            str = node.children[0]
            if str =~ /\A([A-Z][a-z]\w*)\./
              name = $1
              @rails_test_models << name unless @rails_test_models.include?(name)
            end
          end

          # Recurse into children
          node.children.each do |child|
            collect_test_model_references(child, visited) if child.respond_to?(:type)
          end
        end

        # Seed @rails_test_models from cross-file metadata (populated by model filter)
        def seed_models_from_metadata
          return unless @options[:metadata] && @options[:metadata]['models']
          models = @options[:metadata]['models']
          models.each do |name, _meta| # Pragma: entries
            @rails_test_models << name unless @rails_test_models.include?(name)
          end
        end

        # Generate import AST nodes for referenced models, controllers, and path helpers.
        # Uses metadata to determine file paths and import mode (eject vs. virtual).
        def build_test_imports
          imports = []

          # System test imports don't depend on metadata
          if @rails_test_has_system_test
            system_helpers = [:visit, :fillIn, :clickButton, :clickOn, :acceptConfirm, :findField, :findButton, :cleanup]
            system_consts = system_helpers.map { |name| s(:const, nil, name) }
            imports.push(s(:import, ['juntos/system_test.mjs'], system_consts))
          end

          meta = @options[:metadata]
          return imports unless meta

          import_mode = meta['import_mode']
          file = @options[:file]

          if import_mode == 'eject' && file
            # Eject mode: relative paths to .js files
            test_dir = File.dirname(file)
            depth = test_dir.split('/').length
            prefix = '../' * depth

            # Model imports: import { Card } from '../../../app/models/card.js'
            @rails_test_models.each do |name|
              model_meta = meta['models'] && meta['models'][name]
              if model_meta && model_meta['file']
                model_js = model_meta['file'].sub(/\.rb$/, '.js')
                imports.push(s(:import, [prefix + model_js],
                  [s(:const, nil, name.to_sym)]))
              end
            end

            # Controller imports: import { CardsController } from '../../../app/controllers/cards_controller.js'
            if meta['controller_files']
              @rails_test_controllers.each do |name|
                next if @rails_test_stimulus_controllers.include?(name)
                ctrl_file = nil
                meta['controller_files'].each do |cname, cfile| # Pragma: entries
                  ctrl_file = cfile if cname == name
                end
                if ctrl_file
                  imports.push(s(:import, [prefix + 'app/controllers/' + ctrl_file],
                    [s(:const, nil, name.to_sym)]))
                end
              end
            end

            # Stimulus controller imports: import ChatController from '../../../app/javascript/controllers/chat_controller.js'
            @rails_test_stimulus_controllers.each do |name|
              stim_file = name.gsub(/([A-Z])/) { |m| '_' + m.downcase }.sub(/^_/, '') + '.js'
              imports.push(s(:import, [prefix + 'app/javascript/controllers/' + stim_file],
                s(:const, nil, name.to_sym)))
            end

            # Path helper imports: import { cards_path, ... } from '../../../config/paths.js'
            if @rails_test_path_helpers.length > 0
              helper_consts = []
              @rails_test_path_helpers.each do |name|
                helper_consts.push(s(:const, nil, name.to_sym))
              end
              imports.push(s(:import, [prefix + 'config/paths.js'], helper_consts))
            end

            # Fixture import: import { fixtures } from '../../../test/fixtures.mjs'
            plan = meta['fixture_plan']
            if plan && plan['replacements']
              imports.push(s(:import, [prefix + 'test/fixtures.mjs'],
                [s(:const, nil, :fixtures)]))
            end

          elsif import_mode == 'virtual'
            # Virtual mode: import from virtual modules
            if @rails_test_models.length > 0
              model_consts = []
              @rails_test_models.each do |name|
                model_consts.push(s(:const, nil, name.to_sym))
              end
              imports.push(s(:import, ['juntos:models'], model_consts))
            end

            @rails_test_controllers.each do |name|
              next if @rails_test_stimulus_controllers.include?(name)
              # Controllers import from .rb paths (Vite transforms them).
              # Prefer metadata when available; fall back to regex derivation.
              ctrl_file = nil
              if meta['controller_files']
                meta['controller_files'].each do |cname, cfile| # Pragma: entries
                  ctrl_file = cfile if cname == name
                end
              end
              if ctrl_file
                ctrl_rb = ctrl_file.sub(/\.js$/, '.rb')
              else
                ctrl_rb = name.gsub(/([A-Z])/) { |m| '_' + m.downcase }.sub(/^_/, '') + '.rb'
              end
              imports.push(s(:import, ['../../app/controllers/' + ctrl_rb],
                [s(:const, nil, name.to_sym)]))
            end

            # Stimulus controller imports: import ChatController from '../../app/javascript/controllers/chat_controller.rb'
            @rails_test_stimulus_controllers.each do |name|
              stim_file = name.gsub(/([A-Z])/) { |m| '_' + m.downcase }.sub(/^_/, '') + '.rb'
              imports.push(s(:import, ['../../app/javascript/controllers/' + stim_file],
                s(:const, nil, name.to_sym)))
            end

            if @rails_test_path_helpers.length > 0
              helper_consts = []
              @rails_test_path_helpers.each do |name|
                helper_consts.push(s(:const, nil, name.to_sym))
              end
              imports.push(s(:import, ['juntos:paths'], helper_consts))
            end
          end

          imports
        end

        # Build AST nodes for global Current attribute assignments from metadata.
        # Returns nodes like: Current.account = fixtures.accounts_37s (eject)
        # or Current.account = _fixtures.accounts_37s (virtual)
        def build_global_current_nodes
          attrs = @options[:metadata] && @options[:metadata]['current_attributes']
          return [] unless attrs

          import_mode = @options[:metadata] && @options[:metadata]['import_mode']
          fixture_var = (import_mode == 'eject') ? :fixtures : :_fixtures

          nodes = []
          attrs.each do |attr_entry|
            attr_name = attr_entry['attr']
            table = attr_entry['table']
            fixture = attr_entry['fixture']

            # Build fixtures.table_fixture reference
            var_name = "#{table}_#{fixture}"
            fixture_ref = s(:attr, s(:lvar, fixture_var), var_name.to_sym)

            # Current.attr = fixtures.table_fixture
            nodes.push(s(:send, s(:const, nil, :Current), :"#{attr_name}=", fixture_ref))
          end

          nodes
        end

        # Check if an AST node contains Current.xxx = ... assignments
        def has_current_assignments(node)
          return false unless node.respond_to?(:type)

          if node.type == :send && node.children[0].respond_to?(:type) &&
             node.children[0].type == :const &&
             node.children[0].children[1] == :Current &&
             node.children[1].to_s.end_with?('=')
            return true
          end

          node.children.any? { |c| c.respond_to?(:type) && has_current_assignments(c) }
        end

        # Build a standalone beforeEach for global Current attributes.
        # Used when no setup block handles Current assignments.
        # Returns nil in eject mode (Current setup is in shared fixtures module).
        def build_current_standalone_before_each
          import_mode = @options[:metadata] && @options[:metadata]['import_mode']
          return nil if import_mode == 'eject'

          attrs = @options[:metadata] && @options[:metadata]['current_attributes']
          return nil unless attrs && attrs.length > 0

          nodes = build_global_current_nodes
          return nil if nodes.empty?

          settle = s(:await!, s(:const, nil, :Current), :settle)
          body = s(:begin, *nodes, settle)
          async_fn = s(:async, nil, s(:args), body)
          s(:send, nil, :beforeEach, async_fn)
        end

        # Build fixture setup nodes (let _fixtures = {} and beforeEach block)
        # from the pre-computed fixture plan in metadata.
        # In eject mode: returns empty (import is added at top level via build_test_imports).
        # In virtual mode: generates let _fixtures = {} + beforeEach setupCode.
        def build_fixture_nodes
          plan = @options[:metadata] && @options[:metadata]['fixture_plan']
          import_mode = @options[:metadata] && @options[:metadata]['import_mode']

          # Eject mode: fixture import goes at top level (build_test_imports), not inside describe
          return [] if import_mode == 'eject'

          # Virtual/dev mode: existing per-file fixture setup
          return [] unless plan && plan['setupCode']

          # Add fixture model names to @rails_test_models for import generation
          if plan['fixtureModels']
            plan['fixtureModels'].each do |name|
              @rails_test_models << name unless @rails_test_models.include?(name)
            end
          end

          nodes = []

          # let _fixtures = {};
          nodes.push(s(:lvasgn, :_fixtures, s(:hash)))

          # beforeEach(async () => { ... }) as raw JS
          nodes.push(s(:jsraw, plan['setupCode']))

          nodes
        end

        # Pre-resolve fixture references in the AST tree before wrap_ar_operations.
        # This ensures fixture refs like cards(:logo) become fixtures.cards_logo (eject)
        # or _fixtures.cards_logo (virtual) so AR wrapping can detect .reload/.save chains.
        def resolve_fixture_refs_in_tree(node)
          return node unless node.respond_to?(:type)

          plan = @options[:metadata] && @options[:metadata]['fixture_plan']
          return node unless plan && plan['replacements']

          import_mode = @options[:metadata] && @options[:metadata]['import_mode']
          fixture_var = (import_mode == 'eject') ? :fixtures : :_fixtures

          # Check if this node is a fixture ref: s(:send, nil, :cards, s(:sym, :logo))
          # Also handles string args: s(:send, nil, :accounts, s(:str, "37s"))
          if node.type == :send && node.children[0].nil? &&
             node.children.length == 3 &&
             (node.children[2]&.type == :sym || node.children[2]&.type == :str)
            method_name = node.children[1].to_s
            if method_name =~ /\A[a-z]/ &&
               (method_name.end_with?('s') || method_name == 'people')
              fixture_key = node.children[2].children.first.to_s
              lookup = method_name + ':' + fixture_key
              var_name = plan['replacements'][lookup]
              if var_name
                return s(:attr, s(:lvar, fixture_var), var_name.to_sym)
              end
            end
          end

          # Recurse into children
          new_children = node.children.map do |child|
            child.respond_to?(:type) ? resolve_fixture_refs_in_tree(child) : child
          end
          node.updated(nil, new_children)
        end

        # Wrap AR operations with await - delegates to shared helper.
        # Pre-resolves fixture refs so that AR wrapping sees :attr nodes.
        def wrap_test_ar_operations(node)
          resolved = resolve_fixture_refs_in_tree(node)
          # Pass model metadata so wrap_ar_operations can detect custom instance methods
          metadata = @options ? @options[:metadata] : nil
          model_meta = metadata ? metadata['models'] : nil
          ActiveRecordHelpers.wrap_ar_operations(resolved, @rails_test_models, model_meta)
        end

        # Convert sends with receivers in statement position to await!
        # In Ruby, `card.close` or `card.close(user: x)` as standalone statements
        # are always method calls with side effects. In JS, zero-arg sends would
        # be property access without this transform. Using await! forces both
        # parens (method call) and async (await). This catches concern methods
        # like close, reopen, postpone that wrap_test_ar_operations doesn't
        # know about. Sends without a receiver (like assert_equal) are not
        # affected — they're bare function calls handled by the assertion
        # transform or left as-is.
        #
        # Uses cross-file metadata (when available) to skip known-sync methods
        # like enum predicates (card.closed?) which should not be awaited.
        def ensure_statement_method_calls(node)
          return node unless node.respond_to?(:type) && node.type == :begin

          new_children = node.children.map do |child|
            if child.respond_to?(:type) && child.type == :send &&
               child.children[0]  # has a receiver (not bare function call)
              if sync_statement_send?(child) || child.children[1].to_s.end_with?('=')
                child  # known sync or setter — leave as-is, no await
              else
                child.updated(:await!)
              end
            elsif child.respond_to?(:type) && child.type == :begin
              ensure_statement_method_calls(child)
            else
              child
            end
          end
          node.updated(nil, new_children)
        end

        # Check if a statement-position send is known to be synchronous.
        # Uses cross-file metadata populated by the model filter.
        def sync_statement_send?(node)
          method = node.children[1]
          return false unless @options[:metadata] && @options[:metadata]['models']

          method_str = method.to_s
          is_sync = false

          # Check all models for enum predicates and bangs
          @options[:metadata]['models'].each do |_name, model_meta| # Pragma: entries
            if model_meta['enum_predicates'] && model_meta['enum_predicates'].include?(method_str)
              is_sync = true
            end
            if model_meta['enum_bangs'] && model_meta['enum_bangs'].include?(method_str)
              is_sync = true
            end
          end

          is_sync
        end

        # Check if this is a test class (ActiveSupport::TestCase, etc.)
        def test_class?(superclass)
          return false unless superclass&.type == :const

          superclass_name = const_name(superclass)
          [
            'ActiveSupport::TestCase',
            'ActionDispatch::IntegrationTest',
            'ActionDispatch::SystemTestCase',
            'ApplicationSystemTestCase',
            'ActionController::TestCase',
            'ActionMailer::TestCase',
            'ActionView::TestCase',
            'Minitest::Test'
          ].any? { |name| superclass_name.include?(name.split('::').last) }
        end

        # Check if this is an integration test class
        def integration_test_class?(superclass)
          return false unless superclass&.type == :const
          superclass_name = const_name(superclass)
          superclass_name.include?('IntegrationTest')
        end

        # Check if this is a system test class (Capybara-style)
        def system_test_class?(superclass)
          return false unless superclass&.type == :const
          superclass_name = const_name(superclass)
          superclass_name.include?('SystemTestCase')
        end

        # Get fully qualified constant name from AST node
        def const_name(node)
          return '' unless node&.type == :const
          parent = node.children[0]
          name = node.children[1].to_s
          parent ? "#{const_name(parent)}::#{name}" : name
        end

        # Transform class body - process children but strip the :begin wrapper
        def transform_class_body(node)
          return nil unless node

          if node.type == :begin
            children = node.children.map { |child| process(child) }.compact
            # Filter out hide nodes (from stripped require statements)
            children = children.reject { |c| c.respond_to?(:type) && c.type == :hide }
            children.length == 1 ? children.first : s(:begin, *children)
          else
            process(node)
          end
        end

        # Transform minitest assertions to vitest expect() calls
        def transform_assertion(target, method, args)
          return nil unless target.nil?

          case method
          when :assert
            # assert x -> expect(x).toBeTruthy()
            s(:send!, s(:send, nil, :expect, process(args.first)), :toBeTruthy)

          when :assert_not, :refute
            # assert_not x / refute x -> expect(x).toBeFalsy()
            s(:send!, s(:send, nil, :expect, process(args.first)), :toBeFalsy)

          when :assert_equal
            # assert_equal expected, actual -> expect(actual).toBe(expected)
            expected, actual = args[0], args[1]
            if primitive?(expected)
              s(:send, s(:send, nil, :expect, process(actual)), :toBe, process(expected))
            else
              s(:send, s(:send, nil, :expect, process(actual)), :toEqual, process(expected))
            end

          when :assert_not_equal, :refute_equal
            # assert_not_equal expected, actual -> expect(actual).not.toBe(expected)
            expected, actual = args[0], args[1]
            s(:send, s(:attr, s(:send, nil, :expect, process(actual)), :not), :toBe, process(expected))

          when :assert_nil
            # assert_nil x -> expect(x).toBeNull()
            s(:send!, s(:send, nil, :expect, process(args.first)), :toBeNull)

          when :assert_not_nil, :refute_nil
            # assert_not_nil x -> expect(x).not.toBeNull()
            s(:send!, s(:attr, s(:send, nil, :expect, process(args.first)), :not), :toBeNull)

          when :assert_includes
            # assert_includes collection, item -> expect(await collection).toContain(item)
            # Wrap with await since collections may be async (has_many returns CollectionProxy)
            collection, item = args[0], args[1]
            s(:send, s(:send, nil, :expect, s(:send, nil, :await, process(collection))), :toContain, process(item))

          when :assert_not_includes, :refute_includes
            # assert_not_includes collection, item -> expect(await collection).not.toContain(item)
            collection, item = args[0], args[1]
            s(:send, s(:attr, s(:send, nil, :expect, s(:send, nil, :await, process(collection))), :not), :toContain, process(item))

          when :assert_respond_to
            # assert_respond_to obj, method -> expect(typeof obj.method).toBe('function')
            obj, meth = args[0], args[1]
            method_name = meth.type == :sym ? meth.children.first : meth
            s(:send,
              s(:send, nil, :expect,
                s(:send, nil, :typeof, s(:attr, process(obj), method_name))),
              :toBe, s(:str, 'function'))

          when :assert_empty
            # assert_empty x -> expect(x).toHaveLength(0)
            s(:send, s(:send, nil, :expect, process(args.first)), :toHaveLength, s(:int, 0))

          when :assert_match
            # assert_match pattern, string -> expect(string).toMatch(pattern)
            pattern, string = args[0], args[1]
            s(:send, s(:send, nil, :expect, process(string)), :toMatch, process(pattern))

          when :assert_instance_of
            # assert_instance_of klass, obj -> expect(obj).toBeInstanceOf(klass)
            klass, obj = args[0], args[1]
            s(:send, s(:send, nil, :expect, process(obj)), :toBeInstanceOf, process(klass))

          when :assert_predicate
            # assert_predicate obj, :predicate? -> expect(obj.predicate()).toBeTruthy()
            obj, pred = args[0], args[1]
            pred_name = pred.type == :sym ? pred.children.first : pred
            s(:send!,
              s(:send, nil, :expect, s(:send!, process(obj), pred_name)),
              :toBeTruthy)

          when :assert_operator
            # assert_operator left, op, right -> expect(left op right).toBeTruthy()
            left, op, right = args[0], args[1], args[2]
            op_sym = op.type == :sym ? op.children.first : op
            s(:send!,
              s(:send, nil, :expect, s(:send, process(left), op_sym, process(right))),
              :toBeTruthy)

          else
            nil
          end
        end

        # Transform fixture references: songs(:one) -> _fixtures.songs_one or songs("one")
        def transform_fixture_ref(target, method, args)
          return nil unless target.nil?
          return nil unless args.length == 1 &&
            (args.first&.type == :sym || args.first&.type == :str)

          # Check if this looks like a fixture call (plural model name or known table)
          fixture_name = method.to_s
          return nil unless fixture_name =~ /\A[a-z]/ &&
            (fixture_name.end_with?('s') || fixture_name == 'people')

          fixture_key = args.first.children.first.to_s

          # If a fixture plan exists, produce _fixtures.table_fixture AST node
          # Use :attr to get property access (no parens) since s() nodes lack loc info
          plan = @options[:metadata] && @options[:metadata]['fixture_plan']
          if plan && plan['replacements']
            lookup = fixture_name + ':' + fixture_key
            var_name = plan['replacements'][lookup]
            if var_name
              return s(:attr, s(:lvar, :_fixtures), var_name.to_sym)
            end
          end

          # Fallback: convert symbol arg to string: songs(:one) -> songs("one")
          s(:send, nil, method, s(:str, fixture_key))
        end

        # Check if a node is a primitive literal
        def primitive?(node)
          return false unless node
          [:str, :int, :float, :true, :false, :nil, :sym].include?(node.type)
        end

        # ============================================
        # Integration test (controller) transforms
        # ============================================

        # Build the context() helper function for integration tests
        # Includes a _flash variable that persists across context() calls
        # so flash assertions can read values set by controller actions.
        def build_context_helper
          s(:jsraw, "let _flash = {};\n\nfunction context(params = {}) {\n  _flash = {};\n  return {params, flash: {get(k) {return _flash[k] || \"\"}, set(k, v) {_flash[k] = v}, consumeNotice() {let n = _flash.notice; delete _flash.notice; return {present: !!n, value: n}}, consumeAlert() {let a = _flash.alert; delete _flash.alert; return a || \"\"}}, contentFor: {}}\n}")
        end

        # Standard REST actions — URL helpers with these names map directly
        STANDARD_REST_ACTIONS = %w[new edit].freeze

        # Parse URL helper to extract controller and action info.
        #
        # Handles:
        #   articles_url             -> controller: ArticlesController, plural, REST
        #   article_url(x)           -> controller: ArticlesController, singular, REST
        #   new_article_url          -> controller: ArticlesController, prefix: new
        #   edit_article_url(x)      -> controller: ArticlesController, prefix: edit
        #   redo_heats_url           -> controller: HeatsController, custom_action: redo
        #   book_heats_url(k: v)     -> controller: HeatsController, custom_action: book
        #   person_payments_url(p)   -> nested: person, controller: PaymentsController
        #   person_payment_url(p,x)  -> nested: person, controller: PaymentsController, singular
        #
        # Ambiguity between custom actions and nested resources (e.g., redo_heats vs
        # person_payments) is resolved in transform_http_to_action using the number
        # of positional URL arguments: nested resources pass a parent object.
        #
        def parse_url_helper(method_name)
          name = method_name.to_s.sub(/_url$/, '').sub(/_path$/, '')

          # Check for standard REST prefixes
          prefix = nil
          if name.start_with?('new_')
            prefix = 'new'
            name = name.sub(/^new_/, '')
          elsif name.start_with?('edit_')
            prefix = 'edit'
            name = name.sub(/^edit_/, '')
          end

          # Handle root_url/root_path: use the test class controller
          if name == 'root' && @rails_test_class_controller
            return {
              controller: @rails_test_class_controller,
              base: @rails_test_class_controller.sub(/Controller$/, '').downcase,
              singular: false,
              prefix: nil,
              action_or_parent: nil,
              action: 'root'
            }
          end

          # Check routes metadata for exact mapping
          metadata = @options[:metadata]
          routes_mapping = (metadata ? metadata[:routes_mapping] : nil) || {}
          lookup_key = prefix ? "#{prefix}_#{name}_path" : "#{name}_path"
          if routes_mapping[lookup_key]
            info = routes_mapping[lookup_key]
            result = {
              controller: info[:controller],
              base: info[:base],
              singular: info[:singular],
              prefix: prefix,
              action_or_parent: info[:action_or_parent],
              from_metadata: true
            }
            result[:action] = info[:action] if info[:action]
            return result
          end

          # Fall back to heuristic parsing when no metadata available
          # Use inflector for proper pluralization
          pluralized = Ruby2JS::Inflector.pluralize(name)
          singularized = Ruby2JS::Inflector.singularize(name)
          if name == pluralized || name != singularized
            is_plural = true
            controller_base = name
          else
            is_plural = false
            controller_base = pluralized
          end

          # Check if the full compound name matches the class-derived controller.
          # If so, the entire name is the resource (e.g., age_costs -> AgeCostsController),
          # not a nested/prefixed route (e.g., action "age" on CostsController).
          full_controller = Ruby2JS::Inflector.classify(controller_base) + 'Controller'
          use_full_name = @rails_test_class_controller == full_controller

          # Detect prefix_resource pattern (custom action or nested resource)
          # e.g., redo_heats, book_heats, person_payments, person_payment
          # Also handles new_person_payment, edit_person_payment (prefix already stripped)
          # Parse both interpretations; disambiguate later using arg count.
          # Skip splitting when the full name matches the test class controller.
          action_or_parent = nil
          if name.include?('_') && !use_full_name
            parts = name.split('_')
            # Try splitting from the right: find the longest resource suffix
            (parts.length - 1).downto(1) do |i|
              resource_candidate = parts[i..-1].join('_')
              prefix_candidate = parts[0...i].join('_')
              next if prefix_candidate.empty?

              # Resource must be a plausible name (at least 2 chars)
              if resource_candidate.length > 1
                action_or_parent = prefix_candidate
                rc_plural = Ruby2JS::Inflector.pluralize(resource_candidate)
                rc_singular = Ruby2JS::Inflector.singularize(resource_candidate)
                if resource_candidate == rc_plural || resource_candidate != rc_singular
                  is_plural = true
                  controller_base = resource_candidate
                else
                  is_plural = false
                  controller_base = rc_plural
                end
                break
              end
            end
          end

          controller_name = Ruby2JS::Inflector.classify(controller_base)

          { controller: "#{controller_name}Controller",
            base: controller_base,
            singular: !is_plural,
            prefix: prefix,
            action_or_parent: action_or_parent }
        end

        # Determine controller action from HTTP method + URL helper info
        # is_nested: whether this was determined to be a nested resource
        def determine_action(http_method, url_info, is_nested)
          # Explicit action from metadata (e.g., root route)
          if url_info[:action]
            action = url_info[:action].to_s
            return action == 'new' ? :$new : action.to_sym
          end

          # Custom action (non-nested prefix like redo_heats)
          if url_info[:action_or_parent] && !is_nested
            action_name = url_info[:action_or_parent]
            return action_name == 'new' ? :$new : action_name.to_sym
          end

          if url_info[:prefix] == 'new'
            return :$new
          elsif url_info[:prefix] == 'edit'
            return :edit
          end

          case http_method
          when :get
            url_info[:singular] ? :show : :index
          when :post
            :create
          when :patch, :put
            :update
          when :delete
            :destroy
          else
            http_method
          end
        end

        # Disambiguate action_or_parent: is it a custom action or a nested parent?
        #
        # Rules:
        # - Has REST prefix (new_, edit_) = always nested (new_person_payment = nested)
        # - Plural URL + no positional args = custom action (redo_heats_url)
        # - Plural URL + positional args = nested resource (person_payments_url(@person))
        # - Singular URL + 1 positional arg = could be either; if REST prefix absent,
        #   treat as member action on singular (article_url(@article))
        # - Singular URL + 2+ positional args = nested resource
        #
        def resolve_nested(url_info, url_args)
          return false unless url_info[:action_or_parent]

          # Metadata-based routes always have correct nesting info
          return true if url_info[:from_metadata]

          # new_ and edit_ prefixed URLs with action_or_parent are always nested
          # e.g., new_person_payment_url(@person) -> nested new on payments
          return true if url_info[:prefix]

          if url_info[:singular]
            # Singular: nested if there are 2+ positional args
            url_args.length >= 2
          else
            # Plural: nested if there are positional args (parent object)
            url_args.length >= 1
          end
        end

        # Transform HTTP method call to controller action call
        # e.g., get articles_url -> response = await ArticlesController.index(context())
        def transform_http_to_action(http_method, args)
          return process(s(:send, nil, http_method, *args)) if args.empty?

          url_node = args.first
          params_node = nil
          as_node = nil

          # Extract params and other options from keyword hash
          if args.length > 1 && args[1]&.type == :hash
            args[1].children.each do |pair|
              key = pair.children[0]
              value = pair.children[1]
              if key.type == :sym
                case key.children[0]
                when :params
                  params_node = value
                when :as
                  as_node = value
                end
              end
            end
          end

          # Parse URL helper to get controller and action info
          url_method = nil
          url_args = []
          url_hash_node = nil
          if url_node.type == :send && url_node.children[0].nil?
            url_method = url_node.children[1]
            # Collect positional args and hash args separately
            url_node.children[2..-1].each do |arg|
              if arg.type == :hash
                url_hash_node = arg
              else
                url_args << arg
              end
            end
          elsif url_node.type == :lvar || url_node.type == :ivar
            # Variable reference - can't determine controller, pass through
            return super_send_node(http_method, args)
          end

          return super_send_node(http_method, args) unless url_method

          url_info = parse_url_helper(url_method)
          is_nested = resolve_nested(url_info, url_args)
          action = determine_action(http_method, url_info, is_nested)

          # Track controller reference for import generation
          ctrl_name = url_info[:controller]
          @rails_test_controllers << ctrl_name unless @rails_test_controllers.include?(ctrl_name)

          # Build context arguments from URL hash args and `as:` option
          context_params = []
          if url_hash_node
            url_hash_node.children.each { |c| context_params << c }
          end
          if as_node
            # as: :turbo_stream -> format: "turbo_stream"
            format_value = as_node.type == :sym ? s(:str, as_node.children[0].to_s) : as_node
            context_params << s(:pair, s(:sym, :format), format_value)
          end

          # Note: action_args must be declared before the conditional to avoid
          # block-scoped `let` in JS transpilation (selfhost compatibility).
          action_args = []
          if context_params.any?
            action_args = [s(:send!, nil, :context, process(s(:hash, *context_params)))]
          else
            action_args = [s(:send!, nil, :context)]
          end

          # For nested resources, pass parent id first
          if is_nested && !url_args.empty?
            parent_arg = url_args.shift
            processed_parent = process(parent_arg)
            action_args << s(:attr, processed_parent, :id)
          end

          # For member actions (show, edit, update, destroy), pass id
          if url_info[:singular] && !url_args.empty?
            id_arg = url_args.first
            processed_id = process(id_arg)
            action_args << s(:attr, processed_id, :id)
          end

          # For create/update, pass params
          if params_node
            action_args << process(params_node)
          end

          # Build: response = await ControllerName.action(context(), ...)
          # Then extract notice/alert from response into _flash
          controller_const = s(:const, nil, url_info[:controller].to_sym)
          action_call = s(:send, controller_const, action, *action_args)
          await_call = s(:send, nil, :await, action_call)

          assign = s(:lvasgn, :response, await_call)

          # if (response?.notice) _flash.notice = response.notice
          extract_notice = s(:if,
            s(:jsliteral, "response?.notice"),
            s(:send, s(:lvar, :_flash), :notice=, s(:attr, s(:lvar, :response), :notice)),
            nil)

          s(:begin, assign, extract_notice)
        end

        # Helper to construct a passthrough send node (won't be re-processed by on_send)
        # Uses send! to mark as already processed, avoiding infinite recursion
        def super_send_node(method, args)
          s(:send!, nil, method, *process_all(args))
        end

        # Transform assert_response to expect() calls.
        #
        # Transpiled controller actions return:
        #   {redirect: path}  for redirects
        #   {render: view}    for validation errors (re-rendered form)
        #   string/view       for successful renders
        #
        # So we map Rails status categories to property checks:
        #   :success                -> expect(response.redirect).toBeUndefined()
        #   :redirect               -> expect(response.redirect).toBeDefined()
        #   :unprocessable_entity   -> expect(response.render).toBeDefined()
        #   :no_content / :ok etc.  -> expect(response.redirect).toBeUndefined()
        #
        # Redirect status codes (301, 302, 303, 307, 308) check redirect property.
        # Client/server error codes (4xx, 5xx) check render property.
        # Success codes (2xx) check absence of redirect.
        #
        def transform_assert_response(args)
          return nil if args.empty?

          status = args.first
          if status.type == :sym
            sym = status.children.first
            case sym
            when :success, :ok, :no_content, :created, :accepted
              # Successful response — not a redirect
              # expect(response.redirect).toBeUndefined()
              s(:send!, s(:send, nil, :expect, s(:attr, s(:lvar, :response), :redirect)), :toBeUndefined)
            when :redirect, :moved_permanently, :found, :see_other
              # Redirect response
              # expect(response.redirect).toBeDefined()
              s(:send!, s(:send, nil, :expect, s(:attr, s(:lvar, :response), :redirect)), :toBeDefined)
            when :unprocessable_entity, :unprocessable_content
              # Validation error — re-rendered form
              # expect(response.render).toBeDefined()
              s(:send!, s(:send, nil, :expect, s(:attr, s(:lvar, :response), :render)), :toBeDefined)
            when :not_found, :forbidden, :unauthorized, :bad_request,
                 :method_not_allowed, :not_acceptable, :conflict, :gone,
                 :too_many_requests, :internal_server_error, :not_implemented,
                 :bad_gateway, :service_unavailable, :not_modified
              # Error/other status — check render property
              # expect(response.render).toBeDefined()
              s(:send!, s(:send, nil, :expect, s(:attr, s(:lvar, :response), :render)), :toBeDefined)
            else
              # Unknown symbol — fall back to render check
              s(:send!, s(:send, nil, :expect, s(:attr, s(:lvar, :response), :render)), :toBeDefined)
            end
          elsif status.type == :int
            # Numeric status code — categorize by range
            code = status.children.first
            if code >= 300 && code < 400
              # Redirect range
              s(:send!, s(:send, nil, :expect, s(:attr, s(:lvar, :response), :redirect)), :toBeDefined)
            elsif code >= 400
              # Client/server error range
              s(:send!, s(:send, nil, :expect, s(:attr, s(:lvar, :response), :render)), :toBeDefined)
            else
              # 2xx success range
              s(:send!, s(:send, nil, :expect, s(:attr, s(:lvar, :response), :redirect)), :toBeUndefined)
            end
          else
            nil
          end
        end

        # Transform assert_redirected_to url -> expect(String(response.redirect)).toBe(String(url))
        # Path helpers return objects with toString(), so wrap both sides with
        # String() since toBe uses Object.is (===). This applies to both virtual
        # and eject modes since both use createPathHelper.
        def transform_assert_redirected_to(args)
          return nil if args.empty?

          url_node = process(args.first)

          # Force parens on zero-arg path helpers so String(messages_path())
          # doesn't become String(messages_path) (function reference)
          if url_node.type == :send && url_node.children[0].nil? && url_node.children.length == 2
            url_node = s(:send!, *url_node.children)
          end

          # expect(String(response.redirect)).toBe(String(url))
          s(:send,
            s(:send, nil, :expect, s(:send!, nil, :String, s(:attr, s(:lvar, :response), :redirect))),
            :toBe, s(:send!, nil, :String, url_node))
        end

        # Transform Capybara-style system test methods
        # visit, fill_in, click_button, assert_field, assert_selector, assert_text
        def transform_system_test_method(target, method, args)
          return nil unless target.nil?

          @rails_test_has_system_test = true

          case method
          when :visit
            # visit messages_url -> await visit(messages_path())
            return nil if args.empty?
            url_node = process(args.first)
            s(:send, nil, :await, s(:send!, nil, :visit, url_node))

          when :fill_in
            # fill_in "locator", with: "value" -> await fillIn("locator", "value")
            return nil if args.length < 2
            locator = process(args[0])
            value_hash = args[1]
            return nil unless value_hash.type == :hash
            value_node = nil
            value_hash.children.each do |pair|
              if pair.children[0].type == :sym && pair.children[0].children[0] == :with
                value_node = process(pair.children[1])
              end
            end
            return nil unless value_node
            s(:send, nil, :await, s(:send!, nil, :fillIn, locator, value_node))

          when :click_button
            # click_button "Send" -> await clickButton("Send")
            return nil if args.empty?
            text = process(args.first)
            s(:send, nil, :await, s(:send!, nil, :clickButton, text))

          when :click_on, :click_link
            # click_on "Studios" -> await clickOn("Studios")
            return nil if args.empty?
            text = process(args.first)
            s(:send, nil, :await, s(:send!, nil, :clickOn, text))

          when :assert_field
            # assert_field "locator", with: "value" -> expect(findField("locator").value).toBe("value")
            return nil if args.empty?
            locator = process(args[0])
            if args.length >= 2 && args[1].type == :hash
              value_node = nil
              args[1].children.each do |pair|
                if pair.children[0].type == :sym && pair.children[0].children[0] == :with
                  value_node = process(pair.children[1])
                end
              end
              if value_node
                return s(:send,
                  s(:send, nil, :expect,
                    s(:attr, s(:send!, nil, :findField, locator), :value)),
                  :toBe, value_node)
              end
            end
            # assert_field "locator" (existence check)
            s(:send,
              s(:send, nil, :expect, s(:send!, nil, :findField, locator)),
              :toBeTruthy)

          when :assert_selector
            # assert_selector "css", text: "content"
            return nil if args.empty?
            selector = process(args[0])
            if args.length >= 2 && args[1].type == :hash
              text_node = nil
              args[1].children.each do |pair|
                if pair.children[0].type == :sym && pair.children[0].children[0] == :text
                  text_node = process(pair.children[1])
                end
              end
              if text_node
                # expect(document.querySelector("css").textContent).toContain("text")
                return s(:send,
                  s(:send, nil, :expect,
                    s(:attr,
                      s(:send, s(:lvar, :document), :querySelector, selector),
                      :textContent)),
                  :toContain, text_node)
              end
            end
            # assert_selector "css" (existence check)
            s(:send,
              s(:send, nil, :expect,
                s(:send, s(:lvar, :document), :querySelector, selector)),
              :toBeTruthy)

          when :assert_text
            # assert_text "content" -> expect(document.body.textContent).toContain("content")
            return nil if args.empty?
            text = process(args.first)
            s(:send,
              s(:send, nil, :expect,
                s(:attr, s(:attr, s(:lvar, :document), :body), :textContent)),
              :toContain, text)

          when :assert_no_selector
            # assert_no_selector "css" -> expect(document.querySelector("css")).toBeNull()
            return nil if args.empty?
            selector = process(args[0])
            s(:send!,
              s(:send, nil, :expect,
                s(:send, s(:lvar, :document), :querySelector, selector)),
              :toBeNull)

          when :assert_no_text
            # assert_no_text "content" -> expect(document.body.textContent).not.toContain("content")
            return nil if args.empty?
            text = process(args.first)
            s(:send,
              s(:attr,
                s(:send, nil, :expect,
                  s(:attr, s(:attr, s(:lvar, :document), :body), :textContent)),
                :not),
              :toContain, text)

          else
            nil
          end
        end

        # Transform connect_stimulus "identifier", ControllerClass
        # Emits: document.body.innerHTML = response
        #        _stimulusApp = Application.start()
        #        _stimulusApp.register("identifier", ControllerClass)
        #        await new Promise(resolve => setTimeout(resolve, 0))
        def transform_connect_stimulus(args)
          identifier = args[0].children.first  # string value
          controller_const = args[1]            # :const node
          controller_name = controller_const.children.last.to_s

          # Track this as a stimulus controller (not a Rails controller)
          unless @rails_test_stimulus_controllers.include?(controller_name)
            @rails_test_stimulus_controllers << controller_name
          end

          # Emit import { Application } from "@hotwired/stimulus" once
          unless @rails_test_has_stimulus
            self.prepend_list << s(:import, ['@hotwired/stimulus'],
              [s(:const, nil, :Application)])
          end

          @rails_test_has_stimulus = true

          # Build four statements:
          # 1. document.body.innerHTML = response
          innerHTML_assign = s(:send,
            s(:attr, s(:lvar, :document), :body),
            :innerHTML=, s(:lvar, :response))

          # 2. _stimulusApp = Application.start()
          app_start = s(:lvasgn, :_stimulusApp,
            s(:send, s(:const, nil, :Application), :start))

          # 3. _stimulusApp.register("identifier", ControllerClass)
          app_register = s(:send, s(:lvar, :_stimulusApp), :register,
            s(:str, identifier), s(:const, nil, controller_name.to_sym))

          # 4. await new Promise(resolve => setTimeout(resolve, 0))
          await_mutation = s(:send, nil, :await,
            s(:send, s(:const, nil, :Promise), :new,
              s(:block, s(:send, nil, :lambda), s(:args, s(:arg, :resolve)),
                s(:send, nil, :setTimeout, s(:lvar, :resolve), s(:int, 0)))))

          s(:begin, innerHTML_assign, app_start, app_register, await_mutation)
        end

        # Transform assert_select (non-block forms)
        # assert_select "h1" -> existence check
        # assert_select "h1", "text" -> text content check
        # assert_select "h1", /pat/ -> text match check
        # assert_select "h1", count: 3 -> count check
        # assert_select "h1", false -> non-existence check
        # assert_select "h1", 3 -> count shorthand
        def transform_assert_select(args)
          return nil if args.empty?

          selector_node = args[0]
          return nil unless selector_node.type == :str || selector_node.type == :dstr

          # Check for ? substitution: next non-hash arg replaces ? in selector
          selector_str = selector_node.type == :str ? selector_node.children.first : nil
          sub_arg = nil
          remaining_args = args[1..-1]

          if selector_str && selector_str.include?('?') && remaining_args.length > 0 &&
             remaining_args.first.type != :hash
            sub_arg = remaining_args.shift
          end

          base = assert_select_query_base
          innerHTML_node = assert_select_innerHTML

          # Build the selector node (possibly with ? substitution)
          sel_node = build_selector_node(selector_node, sub_arg)

          if remaining_args.empty?
            # assert_select "h1" -> existence check
            checks = [build_existence_check(base, sel_node)]
            return innerHTML_node ? s(:begin, innerHTML_node, *checks) : checks.first
          end

          second = remaining_args.first

          case second.type
          when :str
            # assert_select "h1", "Welcome" -> text content check
            checks = [build_text_check(base, sel_node, :toContain, process(second))]
            return innerHTML_node ? s(:begin, innerHTML_node, *checks) : checks.first

          when :regexp
            # assert_select "h1", /Welcome/ -> regex match check
            checks = [build_text_check(base, sel_node, :toMatch, process(second))]
            return innerHTML_node ? s(:begin, innerHTML_node, *checks) : checks.first

          when :false
            # assert_select "h1", false -> non-existence
            checks = [build_count_check(base, sel_node, s(:int, 0))]
            return innerHTML_node ? s(:begin, innerHTML_node, *checks) : checks.first

          when :int
            # assert_select "h1", 3 -> count shorthand
            checks = [build_count_check(base, sel_node, process(second))]
            return innerHTML_node ? s(:begin, innerHTML_node, *checks) : checks.first

          when :hash
            # assert_select "h1", count: 3, text: "Hi"
            checks = build_hash_checks(base, sel_node, second)
            return innerHTML_node ? s(:begin, innerHTML_node, *checks) : (checks.length == 1 ? checks.first : s(:begin, *checks))

          else
            # assert_select "h1", @article.title -> dynamic text content check
            checks = [build_text_check(base, sel_node, :toContain, process(second))]
            return innerHTML_node ? s(:begin, innerHTML_node, *checks) : checks.first
          end

          nil
        end

        # Transform assert_select block form
        # assert_select "ul" do ... end -> scoped queries
        def transform_assert_select_block(call, body)
          args = call.children[2..-1]
          return nil if args.empty?

          selector_node = args[0]
          return nil unless selector_node.type == :str || selector_node.type == :dstr

          base = assert_select_query_base
          innerHTML_node = assert_select_innerHTML
          sel_node = build_selector_node(selector_node, nil)

          # _scope = base.querySelectorAll(selector)
          scope_assign = s(:lvasgn, :_scope,
            s(:send, base, :querySelectorAll, sel_node))

          # Process body with scope set
          old_scope = @rails_test_assert_select_scope
          @rails_test_assert_select_scope = :_scope
          processed_body = process(body)
          @rails_test_assert_select_scope = old_scope

          parts = []
          parts << innerHTML_node if innerHTML_node
          parts << scope_assign
          parts << processed_body

          s(:begin, *parts)
        end

        # Returns the base element for querySelector calls
        def assert_select_query_base
          if @rails_test_assert_select_scope
            # Inside a block: use _scope[0]
            s(:send, s(:lvar, @rails_test_assert_select_scope), :[], s(:int, 0))
          else
            s(:attr, s(:lvar, :document), :body)
          end
        end

        # Returns innerHTML assignment node, or nil if inside a scoped block
        def assert_select_innerHTML
          return nil if @rails_test_assert_select_scope
          s(:send,
            s(:attr, s(:lvar, :document), :body),
            :innerHTML=, s(:lvar, :response))
        end

        # Build selector node, handling ? substitution
        def build_selector_node(selector_node, sub_arg)
          if sub_arg
            # Replace ? with interpolated value wrapped in CSS quotes: `a[href="${expr}"]`
            # Quotes are needed because substituted values may contain special CSS
            # characters like [] (e.g. input[name="article[title]"])
            selector_str = selector_node.children.first
            parts = selector_str.split('?', 2)
            children = []
            children << s(:str, parts[0] + '"')
            children << s(:begin, process(sub_arg))
            children << s(:str, '"' + parts[1])
            s(:dstr, *children)
          else
            process(selector_node)
          end
        end

        # Build: expect(base.querySelectorAll(sel).length).toBeGreaterThanOrEqual(1)
        def build_existence_check(base, sel_node)
          query = s(:attr,
            s(:send, base, :querySelectorAll, sel_node),
            :length)
          s(:send,
            s(:send, nil, :expect, query),
            :toBeGreaterThanOrEqual, s(:int, 1))
        end

        # Build: expect(base.querySelectorAll(sel)).toHaveLength(n)
        def build_count_check(base, sel_node, count_node)
          query = s(:send, base, :querySelectorAll, sel_node)
          s(:send,
            s(:send, nil, :expect, query),
            :toHaveLength, count_node)
        end

        # Build: expect(base.querySelector(sel).textContent).toContain/toMatch(value)
        def build_text_check(base, sel_node, matcher, value_node)
          text = s(:attr,
            s(:send, base, :querySelector, sel_node),
            :textContent)
          s(:send,
            s(:send, nil, :expect, text),
            matcher, value_node)
        end

        # Build checks from hash options (count:, minimum:, maximum:, text:)
        def build_hash_checks(base, sel_node, hash_node)
          checks = []
          opts = {}

          hash_node.children.each do |pair|
            key = pair.children[0]
            val = pair.children[1]
            key_name = key.type == :sym ? key.children.first : nil
            opts[key_name] = val if key_name
          end

          if opts[:count]
            checks << build_count_check(base, sel_node, process(opts[:count]))
          end

          if opts[:minimum]
            query = s(:attr,
              s(:send, base, :querySelectorAll, sel_node),
              :length)
            checks << s(:send,
              s(:send, nil, :expect, query),
              :toBeGreaterThanOrEqual, process(opts[:minimum]))
          end

          if opts[:maximum]
            query = s(:attr,
              s(:send, base, :querySelectorAll, sel_node),
              :length)
            checks << s(:send,
              s(:send, nil, :expect, query),
              :toBeLessThanOrEqual, process(opts[:maximum]))
          end

          if opts[:text]
            text_val = opts[:text]
            matcher = text_val.type == :regexp ? :toMatch : :toContain
            checks << build_text_check(base, sel_node, matcher, process(text_val))
          end

          # If no recognized keys, fall back to existence check
          checks << build_existence_check(base, sel_node) if checks.empty?

          checks
        end

        # Transform URL helper to path helper
        # articles_url -> articles_path()
        # article_url(@article) -> article_path(article)
        def transform_url_to_path(method, args)
          path_method = method.to_s.sub(/_url$/, '_path').to_sym

          # Track path helper for import generation
          path_str = path_method.to_s
          @rails_test_path_helpers << path_str unless @rails_test_path_helpers.include?(path_str)

          if args.empty?
            s(:send!, nil, path_method)
          else
            s(:send, nil, path_method, *process_all(args))
          end
        end

        # Counter for unique variable names in nested assert_difference
        def next_count_var_suffix
          @rails_test_count_var ||= 0
          @rails_test_count_var += 1
          @rails_test_count_var == 1 ? '' : @rails_test_count_var.to_s
        end

        # Transform assert_difference/assert_no_difference block
        def transform_assert_difference(call, body, no_difference)
          # Extract the expression string and expected difference
          diff_args = call.children[2..-1]
          return super unless diff_args.length >= 1

          expr_node = diff_args[0]
          # Default difference is 1 for assert_difference, 0 for assert_no_difference
          diff_value = no_difference ? 0 : 1
          diff_node = s(:int, diff_value)

          if diff_args.length >= 2 && !no_difference
            val_node = diff_args[1]
            if val_node.type == :int
              diff_value = val_node.children.first
              diff_node = s(:int, diff_value)
            else
              # Runtime expression (e.g., -Table.count) - process it
              diff_node = process(val_node)
            end
          end

          # Parse the count expression to build count call
          count_call = nil
          if expr_node.type == :str
            # String form: "Article.count" -> await Article.count()
            parts = expr_node.children.first.split('.')
            if parts.length == 2
              model_name = parts[0]
              method_name = parts[1]
              # Build const node, handling :: for nested constants
              const_node = model_name.split('::').inject(nil) { |parent, name|
                s(:const, parent, name.to_sym)
              }
              count_call = s(:await!, const_node, method_name.to_sym)
            end
          elsif expr_node.type == :block &&
                (expr_node.children[0]&.type == :lambda ||
                 (expr_node.children[0]&.type == :send &&
                  expr_node.children[0].children[1] == :lambda))
            # Lambda form: -> { cards(:logo).events.count }
            # Process the lambda body first to transform fixture refs, etc.
            lambda_body = process(expr_node.children[2])
            count_call = wrap_test_ar_operations(lambda_body)
            # Ensure the count expression is awaited
            if count_call.respond_to?(:type) && count_call.type == :send
              count_call = count_call.updated(:await!)
            end
          end

          return process(s(:send, nil, no_difference ? :assert_no_difference : :assert_difference, *diff_args)) unless count_call

          # Use unique suffixes for nested assert_difference blocks
          suffix = next_count_var_suffix
          before_var = :"countBefore#{suffix}"
          after_var = :"countAfter#{suffix}"

          # Build the transformed block:
          # let countBefore = await Model.count();
          # ... body ...
          # let countAfter = await Model.count();
          # expect(countAfter - countBefore).toBe(diff_value);
          before_assign = s(:lvasgn, before_var, count_call)

          # Wrap body with AR operations and statement method calls
          wrapped_body = wrap_test_ar_operations(body)
          # Single-statement body: force await if has receiver (method call with side effects)
          if wrapped_body.respond_to?(:type) && wrapped_body.type == :send &&
             wrapped_body.children[0]
            wrapped_body = wrapped_body.updated(:await!)
          end
          # Multi-statement body: apply ensure_statement_method_calls
          wrapped_body = ensure_statement_method_calls(wrapped_body)
          processed_body = process(wrapped_body)

          after_assign = s(:lvasgn, after_var, count_call)

          # expect(countAfter - countBefore).toBe(diff_value)
          diff_expr = s(:send, s(:lvar, after_var), :-, s(:lvar, before_var))
          expect_call = s(:send,
            s(:send, nil, :expect, diff_expr),
            :toBe, diff_node)

          s(:begin, before_assign, processed_body, after_assign, expect_call)
        end
      end
    end

    DEFAULTS.push Rails::Test
  end
end
