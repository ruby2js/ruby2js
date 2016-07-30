require 'ruby2js'

module Ruby2JS
  module Filter
    module MiniTestJasmine
      include SEXP

      def initialize(*args)
        @jasmine_describe = nil
        super
      end

      RELOPS = [:<, :<=, :==, :>=, :>].
        map {|sym| Parser::AST::Node.new :sym, [sym]}

      def on_class(node)
        name, inheritance, *body = node.children
        return super unless inheritance == s(:const, s(:const, nil,
          :Minitest), :Test)

        if body.length == 1 and body.first.type == :begin
          body = body.first.children
        end

        body = body.map do |bnode|
          if bnode.type == :def and bnode.children.first =~ /^test_/
            s(:block, s(:send, nil, :it, s(:str, 
              bnode.children.first.to_s.sub(/^test_/, '').gsub('_', ' '))),
              s(:args), bnode.children.last)
          elsif bnode.type == :def and bnode.children.first == :setup
            s(:block, s(:send, nil, :before), s(:args), bnode.children.last)
          elsif bnode.type == :def and bnode.children.first == :teardown
            s(:block, s(:send, nil, :after), s(:args), bnode.children.last)
          else
            bnode
          end
        end

        process s(:block, s(:send, nil, :describe, s(:sym, name.children[1])),
          s(:args), s(:begin, *body))
      end

      def on_block(node)
        call = node.children.first
        return super unless call.children.first == nil

        if call.children[1] == :describe
          begin
            describe, @jasmine_describe = @jasmine_describe, true
            s(:block, *node.children[0..-2], process(node.children.last))
          ensure
            @jasmine_describe = describe
          end
        elsif @jasmine_describe and call.children[1] == :before
          process s(:block, s(:send, nil, :beforeEach, *call.children[2..-1]),
            *node.children[1..-1])
        elsif @jasmine_describe and call.children[1] == :after
          process s(:block, s(:send, nil, :afterEach, *call.children[2..-1]),
            *node.children[1..-1])
        else
          super
        end
      end

      def on_send(node)
        target, method, *args = node.children
        if target
          if method==:must_be && args.length==2 && RELOPS.include?(args[0])
            process s(:send, nil, :assert_operator, target, *args)
          elsif method==:must_be_close_to && [1,2].include?(args.length)
            process s(:send, nil, :assert_in_delta, target, *args)
          elsif method==:must_be_within_delta && [1,2].include?(args.length)
            process s(:send, nil, :assert_in_delta, target, *args)
          elsif method==:must_be_nil && args.length == 0
            process s(:send, nil, :assert_nil, target)
          elsif method==:must_equal && args.length == 1
            process s(:send, nil, :assert_equal, args.first, target)
          elsif method==:must_include && args.length == 1
            process s(:send, nil, :assert_includes, target, args.first)
          elsif method==:must_match && args.length == 1
            process s(:send, nil, :assert_match, args.first, target)

          elsif method==:cant_be && args.length==2 && RELOPS.include?(args[0])
            process s(:send, nil, :refute_operator, target, *args)
          elsif method==:cant_be_close_to && [1,2].include?(args.length)
            process s(:send, nil, :refute_in_delta, target, *args)
          elsif method==:cant_be_within_delta && [1,2].include?(args.length)
            process s(:send, nil, :refute_in_delta, target, *args)
          elsif method==:cant_be_nil && args.length == 0
            process s(:send, nil, :refute_nil, target)
          elsif method==:cant_equal && args.length == 1
            process s(:send, nil, :refute_equal, args.first, target)
          elsif method==:cant_include && args.length == 1
            process s(:send, nil, :refute_includes, target, args.first)
          elsif method==:cant_match && args.length == 1
            process s(:send, nil, :refute_match, args.first, target)

          else
            super
          end

        else
          if method == :assert and args.length == 1
            process s(:send, s(:send, nil, :expect, args.first), :toBeTruthy)
          elsif method == :assert_equal and args.length == 2
            if [:str, :int, :float].include? args.first.type
              process s(:send, s(:send, nil, :expect, args.last), :toBe,
                args.first)
            else
              process s(:send, s(:send, nil, :expect, args.last), :toEqual,
                args.first)
            end
          elsif method == :assert_in_delta and [2,3].include? args.length
            delta = (args.length == 3 ? args.last : s(:float, 0.001))
            process s(:send, s(:send, nil, :expect, args[1]), :toBeCloseTo,
              args.first, delta)
          elsif method == :assert_includes and args.length == 2
            process s(:send, s(:send, nil, :expect, args.first), :toContain,
              args.last)
          elsif method == :assert_match and args.length == 2
            process s(:send, s(:send, nil, :expect, args.last), :toMatch,
              args.first)
          elsif method == :assert_nil and args.length == 1
            process s(:send, s(:send, nil, :expect, args.first), :toBeNull)
          elsif method==:assert_operator && args.length==3 && args[1].type==:sym
            if args[1].children.first == :<
              process s(:send, s(:send, nil, :expect, args.first),
                :toBeLessThan, args.last)
            elsif args[1].children.first == :<=
              process s(:send, s(:send, nil, :expect, args.last),
                :toBeGreaterThan, args.first)
            elsif args[1].children.first == :>
              process s(:send, s(:send, nil, :expect, args.first),
                :toBeGreaterThan, args.last)
            elsif args[1].children.first == :>=
              process s(:send, s(:send, nil, :expect, args.last),
                :toBeLessThan, args.first)
            elsif args[1].children.first == :==
              process s(:send, nil, :assert_equal, args.last, args.first)
            else
              super
            end

          elsif method == :refute and args.length == 1
            process s(:send, s(:send, nil, :expect, args.first), :toBeFalsy)
          elsif method == :refute_equal and args.length == 2
            if [:str, :int, :float].include? args.first.type
              process s(:send, s(:attr, s(:send, nil, :expect, args.last), 
                :not), :toBe, args.first)
            else
              process s(:send, s(:attr, s(:send, nil, :expect, args.last), 
                :not), :toEqual, args.first)
            end
          elsif method == :refute_in_delta and [2,3].include? args.length
            delta = (args.length == 3 ? args.last : s(:float, 0.001))
            process s(:send, s(:send, nil, :expect, args[1]), :toBeCloseTo,
              args.first, delta)
          elsif method == :refute_includes and args.length == 2
            process s(:send, s(:attr, s(:send, nil, :expect, args.first), 
              :not), :toContain, args.last)
          elsif method == :refute_match and args.length == 2
            process s(:send, s(:attr, s(:send, nil, :expect, args.last), 
              :not), :toMatch, args.first)
          elsif method == :refute_nil and args.length == 1
            process s(:send, s(:attr, s(:send, nil, :expect, args.first), 
              :not), :toBeNull)
          elsif method==:refute_operator && args.length==3 && args[1].type==:sym
            if args[1].children.first == :<=
              process s(:send, s(:send, nil, :expect, args.first),
                :toBeGreaterThan, args.last)
            elsif args[1].children.first == :<
              process s(:send, s(:attr, s(:send, nil, :expect, args.last), 
                :not), :toBeLessThan, args.first)
            elsif args[1].children.first == :>
              process s(:send, s(:attr, s(:send, nil, :expect, args.first),
                :not), :toBeGreaterThan, args.last)
            elsif args[1].children.first == :>=
              process s(:send, s(:send, nil, :expect, args.first),
                :toBeLessThan, args.last)
            elsif args[1].children.first == :==
              process s(:send, nil, :refute_equal, args.last, args.first)
            else
              super
            end

          else
            super
          end
        end
      end
    end

    DEFAULTS.push MiniTestJasmine
  end
end
