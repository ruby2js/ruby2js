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
          @rails_test_integration = false
          @rails_test_response_var = false
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

          # Detect integration test class
          is_integration = integration_test_class?(superclass)

          result = nil
          begin
            @rails_test_describe_depth += 1
            @rails_test_integration = is_integration

            # Collect model references from the body
            collect_test_model_references(body) if body

            # Transform class body
            transformed_body = transform_class_body(body)

            # For integration tests, prepend context helper
            if is_integration && transformed_body
              context_helper = build_context_helper
              if transformed_body.type == :begin
                transformed_body = s(:begin, context_helper, *transformed_body.children)
              else
                transformed_body = s(:begin, context_helper, transformed_body)
              end
            end

            # Build: describe("Name", () => { ... })
            result = s(:block,
              s(:send, nil, :describe, s(:str, describe_name)),
              s(:args),
              transformed_body)
          ensure
            @rails_test_describe_depth -= 1
            @rails_test_integration = false
          end
          result
        end

        # Strip require "test_helper" and handle controller-specific sends
        def on_send(node)
          return super unless is_test_file

          target, method, *args = node.children

          # Strip require "test_helper"
          if target.nil? && method == :require && args.length == 1 &&
             args.first.type == :str && args.first.children.first == 'test_helper'
            return s(:hide)
          end

          # Only transform assertions inside test describe blocks
          if @rails_test_describe_depth > 0
            # Integration test specific transforms
            if @rails_test_integration
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

            wrapped_body = wrap_test_ar_operations(body)
            wrapped_body = ensure_statement_method_calls(wrapped_body)
            processed_body = process(wrapped_body)

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

          when :assert_difference, :assert_no_difference
            return super unless @rails_test_describe_depth > 0
            transform_assert_difference(call, node.children.last, method == :assert_no_difference)

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
        def extract_ivar_names(node)
          names = []
          return names unless node.respond_to?(:type)
          if node.type == :ivasgn
            names << node.children.first.to_s.sub(/^@/, '').to_sym
          elsif node.type == :begin
            node.children.each do |child|
              names.concat(extract_ivar_names(child))
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
        def wrap_test_ar_operations(node)
          ActiveRecordHelpers.wrap_ar_operations(node, @rails_test_models)
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
        def ensure_statement_method_calls(node)
          return node unless node.respond_to?(:type) && node.type == :begin

          new_children = node.children.map do |child|
            if child.respond_to?(:type) && child.type == :send &&
               child.children[0]  # has a receiver (not bare function call)
              # Statement-position send with receiver → method call needing await
              child.updated(:await!)
            elsif child.respond_to?(:type) && child.type == :begin
              ensure_statement_method_calls(child)
            else
              child
            end
          end
          node.updated(nil, new_children)
        end

        # Check if this is a test class (ActiveSupport::TestCase, etc.)
        def test_class?(superclass)
          return false unless superclass&.type == :const

          superclass_name = const_name(superclass)
          [
            'ActiveSupport::TestCase',
            'ActionDispatch::IntegrationTest',
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
            # assert_includes collection, item -> expect(collection).toContain(item)
            collection, item = args[0], args[1]
            s(:send, s(:send, nil, :expect, process(collection)), :toContain, process(item))

          when :assert_not_includes, :refute_includes
            # assert_not_includes collection, item -> expect(collection).not.toContain(item)
            collection, item = args[0], args[1]
            s(:send, s(:attr, s(:send, nil, :expect, process(collection)), :not), :toContain, process(item))

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

        # Transform fixture references: songs(:one) -> songs("one")
        def transform_fixture_ref(target, method, args)
          return nil unless target.nil?
          return nil unless args.length == 1 && args.first&.type == :sym

          # Check if this looks like a fixture call (plural model name or known table)
          fixture_name = method.to_s
          return nil unless fixture_name =~ /\A[a-z]/ &&
            (fixture_name.end_with?('s') || fixture_name == 'people')

          # Convert symbol arg to string: songs(:one) -> songs("one")
          s(:send, nil, method, s(:str, args.first.children.first.to_s))
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

          # Determine if the resource name is plural or singular
          if name.end_with?('s') && name.length > 1
            is_plural = true
            controller_base = name
          else
            is_plural = false
            controller_base = name + 's'
          end

          # Detect prefix_resource pattern (custom action or nested resource)
          # e.g., redo_heats, book_heats, person_payments, person_payment
          # Also handles new_person_payment, edit_person_payment (prefix already stripped)
          # Parse both interpretations; disambiguate later using arg count.
          action_or_parent = nil
          if name.include?('_')
            parts = name.split('_')
            # Try splitting from the right: find the longest resource suffix
            (parts.length - 1).downto(1) do |i|
              resource_candidate = parts[i..-1].join('_')
              prefix_candidate = parts[0...i].join('_')
              next if prefix_candidate.empty?

              # Resource must be a plausible name (at least 2 chars)
              if resource_candidate.length > 1
                action_or_parent = prefix_candidate
                if resource_candidate.end_with?('s')
                  is_plural = true
                  controller_base = resource_candidate
                else
                  is_plural = false
                  controller_base = resource_candidate + 's'
                end
                break
              end
            end
          end

          controller_name = controller_base.split('_').map(&:capitalize).join

          { controller: "#{controller_name}Controller",
            base: controller_base,
            singular: !is_plural,
            prefix: prefix,
            action_or_parent: action_or_parent }
        end

        # Determine controller action from HTTP method + URL helper info
        # is_nested: whether this was determined to be a nested resource
        def determine_action(http_method, url_info, is_nested)
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
          controller_const = s(:const, nil, url_info[:controller].to_sym)
          action_call = s(:send, controller_const, action, *action_args)
          await_call = s(:send, nil, :await, action_call)

          s(:lvasgn, :response, await_call)
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

        # Transform assert_redirected_to url -> expect(response.redirect).toBe(url)
        def transform_assert_redirected_to(args)
          return nil if args.empty?

          url_node = process(args.first)

          # expect(response.redirect).toBe(url)
          s(:send,
            s(:send, nil, :expect, s(:attr, s(:lvar, :response), :redirect)),
            :toBe, url_node)
        end

        # Transform URL helper to path helper
        # articles_url -> articles_path()
        # article_url(@article) -> article_path(article)
        def transform_url_to_path(method, args)
          path_method = method.to_s.sub(/_url$/, '_path').to_sym

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
              count_call = s(:await!,
                s(:const, nil, model_name.to_sym), method_name.to_sym)
            end
          elsif expr_node.type == :block &&
                (expr_node.children[0]&.type == :lambda ||
                 (expr_node.children[0]&.type == :send &&
                  expr_node.children[0].children[1] == :lambda))
            # Lambda form: -> { cards(:logo).events.count }
            lambda_body = expr_node.children[2]
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
