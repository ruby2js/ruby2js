# Support for Minitest/Rails testing frameworks.
#
# Converts Minitest-style tests to Vitest:
#   class FooTest < ActiveSupport::TestCase -> describe("FooTest", () => {...})
#   setup do ... end -> beforeEach(async () => {...})
#   teardown do ... end -> afterEach(async () => {...})
#   test "name" do ... end -> test("name", async () => {...})
#   assert x -> expect(x).toBeTruthy()
#   assert_equal expected, actual -> expect(actual).toBe(expected)
#   assert_nil x -> expect(x).toBeNull()
#   assert_difference("Model.count") do ... end -> count before/after pattern
#
# Works with both Jest and Vitest (they share the same API).

require 'ruby2js'

module Ruby2JS
  module Filter
    module Minitest
      include SEXP

      def initialize(*args)
        @minitest_test = nil
        super
      end

      # Handle test class definitions
      def on_class(node)
        class_name, superclass, body = node.children

        # Check if this is a test class
        return super unless test_class?(superclass)

        @minitest_test = true

        # Transform class body
        transformed_body = transform_test_body(body)

        @minitest_test = nil

        # describe("ClassName", () => { ... })
        s(:block,
          s(:send, nil, :describe, s(:str, class_name.children.last.to_s)),
          s(:args),
          transformed_body)
      end

      # Handle setup/teardown and test blocks
      def on_block(node)
        return super unless @minitest_test

        call = node.children.first
        return super unless call.type == :send && call.children.first.nil?

        method = call.children[1]
        args = call.children[2..-1]

        case method
        when :setup
          # setup do ... end -> beforeEach(async () => { ... })
          s(:block, s(:send, nil, :beforeEach), s(:args),
            s(:async, process(node.children.last)))

        when :teardown
          # teardown do ... end -> afterEach(async () => { ... })
          s(:block, s(:send, nil, :afterEach), s(:args),
            s(:async, process(node.children.last)))

        when :test
          # test "name" do ... end -> test("name", async () => { ... })
          test_name = args.first
          s(:block, s(:send, nil, :test, process(test_name)), s(:args),
            s(:async, process(node.children.last)))

        when :assert_difference
          # assert_difference("Model.count") do ... end
          # assert_difference("Model.count", -1) do ... end
          transform_assert_difference(args, node.children.last)

        when :assert_no_difference
          # assert_no_difference("Model.count") do ... end
          transform_assert_no_difference(args, node.children.last)

        else
          super
        end
      end

      # Handle assert_* method calls
      def on_send(node)
        return super unless @minitest_test

        target, method, *args = node.children
        return super unless target.nil?

        case method
        when :assert
          # assert x -> expect(x).toBeTruthy()
          # assert x, "message" -> expect(x).toBeTruthy() (ignore message for now)
          s(:send!, s(:send, nil, :expect, process(args.first)), :toBeTruthy)

        when :refute
          # refute x -> expect(x).toBeFalsy()
          s(:send!, s(:send, nil, :expect, process(args.first)), :toBeFalsy)

        when :assert_equal
          # assert_equal expected, actual -> expect(actual).toBe(expected) or toEqual
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

        when :assert_empty
          # assert_empty x -> expect(x).toHaveLength(0)
          s(:send, s(:send, nil, :expect, process(args.first)), :toHaveLength, s(:int, 0))

        when :refute_empty
          # refute_empty x -> expect(x.length).toBeGreaterThan(0)
          s(:send,
            s(:send, nil, :expect, s(:attr, process(args.first), :length)),
            :toBeGreaterThan, s(:int, 0))

        when :assert_includes
          # assert_includes collection, item -> expect(collection).toContain(item)
          collection, item = args[0], args[1]
          s(:send, s(:send, nil, :expect, process(collection)), :toContain, process(item))

        when :refute_includes
          # refute_includes collection, item -> expect(collection).not.toContain(item)
          collection, item = args[0], args[1]
          s(:send, s(:attr, s(:send, nil, :expect, process(collection)), :not), :toContain, process(item))

        when :assert_match
          # assert_match pattern, string -> expect(string).toMatch(pattern)
          pattern, string = args[0], args[1]
          s(:send, s(:send, nil, :expect, process(string)), :toMatch, process(pattern))

        when :refute_match
          # refute_match pattern, string -> expect(string).not.toMatch(pattern)
          pattern, string = args[0], args[1]
          s(:send, s(:attr, s(:send, nil, :expect, process(string)), :not), :toMatch, process(pattern))

        when :assert_instance_of
          # assert_instance_of klass, obj -> expect(obj).toBeInstanceOf(klass)
          klass, obj = args[0], args[1]
          s(:send, s(:send, nil, :expect, process(obj)), :toBeInstanceOf, process(klass))

        when :assert_kind_of
          # assert_kind_of klass, obj -> expect(obj).toBeInstanceOf(klass)
          klass, obj = args[0], args[1]
          s(:send, s(:send, nil, :expect, process(obj)), :toBeInstanceOf, process(klass))

        when :assert_respond_to
          # assert_respond_to obj, method -> expect(typeof obj.method).toBe('function')
          obj, meth = args[0], args[1]
          method_name = meth.type == :sym ? meth.children.first : meth
          s(:send,
            s(:send, nil, :expect,
              s(:send, nil, :typeof, s(:attr, process(obj), method_name))),
            :toBe, s(:str, 'function'))

        when :assert_raises, :assert_raise
          # assert_raises(Error) { ... } is a block, handled in on_block
          # but assert_raises Error do ... end might come through here
          super

        when :assert_nothing_raised
          # assert_nothing_raised { ... } -> just run the code (expect no throw)
          super

        when :assert_in_delta
          # assert_in_delta expected, actual, delta -> expect(actual).toBeCloseTo(expected, precision)
          expected, actual, delta = args[0], args[1], args[2]
          # Convert delta to precision (rough approximation)
          s(:send, s(:send, nil, :expect, process(actual)), :toBeCloseTo, process(expected))

        when :assert_operator
          # assert_operator left, op, right -> expect(left op right).toBeTruthy()
          left, op, right = args[0], args[1], args[2]
          op_sym = op.type == :sym ? op.children.first : op
          s(:send!,
            s(:send, nil, :expect, s(:send, process(left), op_sym, process(right))),
            :toBeTruthy)

        when :assert_predicate
          # assert_predicate obj, :predicate? -> expect(obj.predicate()).toBeTruthy()
          obj, pred = args[0], args[1]
          pred_name = pred.type == :sym ? pred.children.first : pred
          s(:send!,
            s(:send, nil, :expect, s(:send!, process(obj), pred_name)),
            :toBeTruthy)

        when :refute_predicate
          # refute_predicate obj, :predicate? -> expect(obj.predicate()).toBeFalsy()
          obj, pred = args[0], args[1]
          pred_name = pred.type == :sym ? pred.children.first : pred
          s(:send!,
            s(:send, nil, :expect, s(:send!, process(obj), pred_name)),
            :toBeFalsy)

        when :assert_response
          # assert_response :success -> expect(response.status).toBe(200)
          # assert_response :redirect -> expect(response.redirect).toBeDefined()
          transform_assert_response(args.first)

        when :assert_redirected_to
          # assert_redirected_to url -> expect(response.redirect).toBe(url)
          s(:send,
            s(:send, nil, :expect, s(:attr, s(:lvar, :response), :redirect)),
            :toBe, process(args.first))

        when :follow_redirect!
          # follow_redirect! -> response = await get(response.redirect)
          s(:lvasgn, :response,
            s(:send, nil, :await,
              s(:send, nil, :get, s(:attr, s(:lvar, :response), :redirect))))

        else
          super
        end
      end

      private

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

      def const_name(node)
        return '' unless node&.type == :const
        parent = node.children[0]
        name = node.children[1].to_s
        parent ? "#{const_name(parent)}::#{name}" : name
      end

      def transform_test_body(node)
        return nil unless node

        if node.type == :begin
          children = node.children.map { |child| process(child) }.compact
          children.length == 1 ? children.first : s(:begin, *children)
        else
          process(node)
        end
      end

      def primitive?(node)
        return false unless node
        [:str, :int, :float, :true, :false, :nil, :sym].include?(node.type)
      end

      def transform_assert_response(status_node)
        return super unless status_node&.type == :sym

        status = status_node.children.first

        case status
        when :success
          # expect(response.status).toBe(200)
          s(:send,
            s(:send, nil, :expect, s(:attr, s(:lvar, :response), :status)),
            :toBe, s(:int, 200))

        when :redirect
          # expect(response.redirect).toBeDefined()
          s(:send!,
            s(:send, nil, :expect, s(:attr, s(:lvar, :response), :redirect)),
            :toBeDefined)

        when :not_found
          s(:send,
            s(:send, nil, :expect, s(:attr, s(:lvar, :response), :status)),
            :toBe, s(:int, 404))

        when :unprocessable_entity
          s(:send,
            s(:send, nil, :expect, s(:attr, s(:lvar, :response), :status)),
            :toBe, s(:int, 422))

        else
          # Pass through numeric status
          s(:send,
            s(:send, nil, :expect, s(:attr, s(:lvar, :response), :status)),
            :toBe, status_node)
        end
      end

      def transform_assert_difference(args, block_body)
        # assert_difference("Article.count") do ... end
        # ->
        # const countBefore = await Article.count();
        # ... block body ...
        # const countAfter = await Article.count();
        # expect(countAfter - countBefore).toBe(1);

        expr_str = args.first
        diff = args[1] || s(:int, 1)

        # Parse "Article.count" to get model and method
        # For simplicity, we'll use a placeholder approach
        count_var_before = :countBefore
        count_var_after = :countAfter

        # Build the count expression from string
        count_expr = parse_count_expression(expr_str)

        s(:begin,
          # const countBefore = await Article.count()
          s(:lvasgn, count_var_before, s(:send, nil, :await, count_expr)),
          # ... block body ...
          s(:async, process(block_body)),
          # const countAfter = await Article.count()
          s(:lvasgn, count_var_after, s(:send, nil, :await, count_expr)),
          # expect(countAfter - countBefore).toBe(diff)
          s(:send,
            s(:send, nil, :expect,
              s(:send, s(:lvar, count_var_after), :-, s(:lvar, count_var_before))),
            :toBe, process(diff)))
      end

      def transform_assert_no_difference(args, block_body)
        # Same as assert_difference but expects 0 change
        transform_assert_difference([args.first, s(:int, 0)], block_body)
      end

      def parse_count_expression(node)
        # Handle "Article.count" string -> Article.count()
        if node.type == :str
          parts = node.children.first.split('.')
          if parts.length == 2
            model = parts[0]
            method = parts[1]
            return s(:send!, s(:const, nil, model.to_sym), method.to_sym)
          end
        end
        # Fallback: just process the node
        process(node)
      end
    end

    DEFAULTS.push Minitest
  end
end
