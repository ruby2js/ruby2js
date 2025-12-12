# Support for Jest/Vitest testing frameworks using RSpec-like Ruby syntax.
#
# Converts RSpec-style tests to Jest:
#   describe/context blocks -> describe()
#   it/specify blocks -> it()/test()
#   before/after hooks -> beforeEach()/afterEach()
#   before(:all)/after(:all) -> beforeAll()/afterAll()
#   expect(x).to eq(y) -> expect(x).toBe(y)
#
# Works with both Jest and Vitest (they share the same API).

require 'ruby2js'

module Ruby2JS
  module Filter
    module Jest
      include SEXP

      def initialize(*args)
        @jest_describe = nil
        super
      end

      # Handle describe/context blocks
      def on_block(node)
        call = node.children.first
        return super unless call.children.first == nil

        method = call.children[1]

        if method == :describe || method == :context
          # describe "something" do ... end -> describe("something", () => { ... })
          begin
            describe, @jest_describe = @jest_describe, true
            args = call.children[2..-1]
            s(:block, s(:send, nil, :describe, *process_all(args)),
              s(:args), process(node.children.last))
          ensure
            @jest_describe = describe
          end

        elsif @jest_describe && (method == :it || method == :specify)
          # it "does something" do ... end -> it("does something", () => { ... })
          args = call.children[2..-1]
          s(:block, s(:send, nil, method == :specify ? :test : :it, *process_all(args)),
            s(:args), process(node.children.last))

        elsif @jest_describe && method == :test
          # test "something" do ... end -> test("something", () => { ... })
          args = call.children[2..-1]
          s(:block, s(:send, nil, :test, *process_all(args)),
            s(:args), process(node.children.last))

        elsif @jest_describe && method == :before
          # before do ... end -> beforeEach(() => { ... })
          # before(:all) do ... end -> beforeAll(() => { ... })
          scope = call.children[2]
          if scope&.type == :sym && scope.children.first == :all
            s(:block, s(:send, nil, :beforeAll), s(:args), process(node.children.last))
          elsif scope&.type == :sym && scope.children.first == :each
            s(:block, s(:send, nil, :beforeEach), s(:args), process(node.children.last))
          else
            s(:block, s(:send, nil, :beforeEach), s(:args), process(node.children.last))
          end

        elsif @jest_describe && method == :after
          # after do ... end -> afterEach(() => { ... })
          # after(:all) do ... end -> afterAll(() => { ... })
          scope = call.children[2]
          if scope&.type == :sym && scope.children.first == :all
            s(:block, s(:send, nil, :afterAll), s(:args), process(node.children.last))
          elsif scope&.type == :sym && scope.children.first == :each
            s(:block, s(:send, nil, :afterEach), s(:args), process(node.children.last))
          else
            s(:block, s(:send, nil, :afterEach), s(:args), process(node.children.last))
          end

        elsif @jest_describe && method == :let
          # let(:name) { value } -> const name = value (hoisted)
          # Note: Jest doesn't have let() - convert to beforeEach assignment
          name = call.children[2]
          if name&.type == :sym
            var_name = name.children.first
            s(:block, s(:send, nil, :beforeEach), s(:args),
              s(:lvasgn, var_name, process(node.children.last)))
          else
            super
          end

        else
          super
        end
      end

      # Handle expect().to matchers
      def on_send(node)
        target, method, *args = node.children

        # expect(x).to eq(y) style
        if target&.type == :send && target.children[1] == :expect
          expectation = target.children[2]

          case method
          when :to
            process_matcher(expectation, args.first, false)
          when :not_to, :to_not
            process_matcher(expectation, args.first, true)
          else
            super
          end

        # Direct Jest-style: expect(x).toBe(y)
        elsif target&.type == :send && target.children[0] == nil &&
              target.children[1] == :expect
          super

        else
          super
        end
      end

      private

      def process_matcher(expectation, matcher, negated)
        return super unless matcher&.type == :send

        matcher_target, matcher_method, *matcher_args = matcher.children

        # Build the expect() call
        expect_call = s(:send, nil, :expect, process(expectation))

        # Add .not if negated
        if negated
          expect_call = s(:attr, expect_call, :not)
        end

        case matcher_method
        when :eq, :eql
          # eq/eql -> toBe for primitives, toEqual for objects
          if matcher_args.first && [:str, :int, :float, :true, :false, :nil].include?(matcher_args.first.type)
            s(:send, expect_call, :toBe, process(matcher_args.first))
          else
            s(:send, expect_call, :toEqual, process(matcher_args.first))
          end

        when :equal
          # equal (identity) -> toBe
          s(:send, expect_call, :toBe, process(matcher_args.first))

        when :be
          if matcher_args.empty?
            # expect(x).to be -> toBeTruthy
            s(:send!, expect_call, :toBeTruthy)
          elsif matcher_args.first&.type == :true
            s(:send, expect_call, :toBe, s(:true))
          elsif matcher_args.first&.type == :false
            s(:send, expect_call, :toBe, s(:false))
          else
            s(:send, expect_call, :toBe, process(matcher_args.first))
          end

        when :be_truthy
          s(:send!, expect_call, :toBeTruthy)

        when :be_falsy, :be_falsey
          s(:send!, expect_call, :toBeFalsy)

        when :be_nil
          s(:send!, expect_call, :toBeNull)

        when :be_undefined
          s(:send!, expect_call, :toBeUndefined)

        when :be_defined
          s(:send!, expect_call, :toBeDefined)

        when :be_nan
          s(:send!, expect_call, :toBeNaN)

        when :be_empty
          s(:send, s(:attr, expect_call, :length), :toBe, s(:int, 0))

        when :include
          s(:send, expect_call, :toContain, process(matcher_args.first))

        when :match
          s(:send, expect_call, :toMatch, process(matcher_args.first))

        when :start_with
          s(:send, expect_call, :toMatch,
            s(:regexp, s(:str, "^" + Regexp.escape(matcher_args.first.children.first.to_s)), s(:regopt)))

        when :end_with
          s(:send, expect_call, :toMatch,
            s(:regexp, s(:str, Regexp.escape(matcher_args.first.children.first.to_s) + "$"), s(:regopt)))

        when :have_key
          s(:send, expect_call, :toHaveProperty, process(matcher_args.first))

        when :have_length, :have_size
          s(:send, expect_call, :toHaveLength, process(matcher_args.first))

        when :be_a, :be_an, :be_kind_of, :be_instance_of
          # be_a(Array) -> toBeInstanceOf(Array)
          s(:send, expect_call, :toBeInstanceOf, process(matcher_args.first))

        when :raise_error
          if matcher_args.empty?
            s(:send!, expect_call, :toThrow)
          else
            s(:send, expect_call, :toThrow, process(matcher_args.first))
          end

        when :be_greater_than, :be_gt
          s(:send, expect_call, :toBeGreaterThan, process(matcher_args.first))

        when :be_greater_than_or_equal_to, :be_gte
          s(:send, expect_call, :toBeGreaterThanOrEqual, process(matcher_args.first))

        when :be_less_than, :be_lt
          s(:send, expect_call, :toBeLessThan, process(matcher_args.first))

        when :be_less_than_or_equal_to, :be_lte
          s(:send, expect_call, :toBeLessThanOrEqual, process(matcher_args.first))

        when :be_within
          # be_within(0.1).of(5) -> toBeCloseTo(5, 1)
          # This is a chained matcher, handle specially
          delta = matcher_args.first
          # Look for .of() in the parent - for now just output toBeCloseTo
          s(:send, expect_call, :toBeCloseTo, process(delta))

        when :have_been_called
          s(:send!, expect_call, :toHaveBeenCalled)

        when :have_been_called_with
          s(:send, expect_call, :toHaveBeenCalledWith, *process_all(matcher_args))

        when :have_been_called_times
          s(:send, expect_call, :toHaveBeenCalledTimes, process(matcher_args.first))

        else
          # Unknown matcher - pass through as camelCase
          camel_method = matcher_method.to_s.gsub(/_([a-z])/) { $1.upcase }
          camel_method = "to" + camel_method[0].upcase + camel_method[1..-1] unless camel_method.start_with?("to")
          if matcher_args.empty?
            s(:send!, expect_call, camel_method.to_sym)
          else
            s(:send, expect_call, camel_method.to_sym, *process_all(matcher_args))
          end
        end
      end
    end

    DEFAULTS.push Jest
  end
end
