require 'minitest/autorun'
require 'ruby2js'
require 'ruby2js/filter_dsl'

describe Ruby2JS::FilterDSL do
  include Ruby2JS::Filter::SEXP

  describe 'pattern matching' do
    it "matches a simple expression" do
      pattern_ast = Ruby2JS.parse('puts(_1)').first
      node_ast = Ruby2JS.parse('puts("hello")').first
      bindings = {}
      result = Ruby2JS::FilterDSL.match_pattern(node_ast, pattern_ast, bindings)
      _(result).must_equal true
      _(bindings[:_1].type).must_equal :str
      _(bindings[:_1].children[0]).must_equal 'hello'
    end

    it "matches a nested expression" do
      pattern_ast = Ruby2JS.parse('Foo.new(_1).bar(_2)').first
      node_ast = Ruby2JS.parse('Foo.new(url).bar(opts)').first
      bindings = {}
      result = Ruby2JS::FilterDSL.match_pattern(node_ast, pattern_ast, bindings)
      _(result).must_equal true
      _(bindings[:_1].children[1]).must_equal :url
      _(bindings[:_2].children[1]).must_equal :opts
    end

    it "rejects a non-matching expression" do
      pattern_ast = Ruby2JS.parse('puts(_1)').first
      node_ast = Ruby2JS.parse('print("hello")').first
      bindings = {}
      result = Ruby2JS::FilterDSL.match_pattern(node_ast, pattern_ast, bindings)
      _(result).must_equal false
    end

    it "matches a constant chain" do
      pattern_ast = Ruby2JS.parse('RQRCode::QRCode.new(_1)').first
      node_ast = Ruby2JS.parse('RQRCode::QRCode.new(data)').first
      bindings = {}
      result = Ruby2JS::FilterDSL.match_pattern(node_ast, pattern_ast, bindings)
      _(result).must_equal true
    end

    it "matches with no placeholders" do
      pattern_ast = Ruby2JS.parse('Rails.logger').first
      node_ast = Ruby2JS.parse('Rails.logger').first
      bindings = {}
      result = Ruby2JS::FilterDSL.match_pattern(node_ast, pattern_ast, bindings)
      _(result).must_equal true
    end
  end

  describe 'replacement application' do
    it "applies a simple replacement" do
      replacement_ast = Ruby2JS.parse('"<svg></svg>"').first
      bindings = {}
      result = Ruby2JS::FilterDSL.apply_replacement(replacement_ast, bindings)
      _(result.type).must_equal :str
      _(result.children[0]).must_equal '<svg></svg>'
    end

    it "substitutes placeholders in replacement" do
      replacement_ast = Ruby2JS.parse('console.log(_1)').first
      arg_node = s(:str, "hello")
      bindings = {_1: arg_node}
      result = Ruby2JS::FilterDSL.apply_replacement(replacement_ast, bindings)
      _(result.type).must_equal :send
      _(result.children[1]).must_equal :log
      _(result.children[2]).must_equal arg_node
    end
  end

  describe 'filter generation' do
    after do
      # Clean up registered filters
      [:TestRewrite, :TestHandler, :TestMultiRewrite, :TestMixed].each do |name|
        Ruby2JS::Filter.send(:remove_const, name) if Ruby2JS::Filter.const_defined?(name)
      end
    end

    it "creates a filter from a rewrite rule" do
      Ruby2JS.filter(:TestRewrite) do
        rewrite 'puts(_1)', to: 'console.log(_1)'
      end

      js = Ruby2JS.convert('puts("hello")',
        filters: [Ruby2JS::Filter::TestRewrite]).to_s
      _(js).must_equal 'console.log("hello")'
    end

    it "creates a filter with custom on_send handler" do
      Ruby2JS.filter(:TestHandler) do
        on_send do |node|
          _receiver, method, *_args = node.children
          if method == :custom_method
            s(:send, nil, :replacedMethod)
          end
        end
      end

      js = Ruby2JS.convert('custom_method',
        filters: [Ruby2JS::Filter::TestHandler]).to_s
      _(js).must_equal 'replacedMethod()'
    end

    it "applies multiple rewrite rules" do
      Ruby2JS.filter(:TestMultiRewrite) do
        rewrite 'puts(_1)', to: 'console.log(_1)'
        rewrite 'p(_1)', to: 'console.log(_1)'
      end

      js1 = Ruby2JS.convert('puts("a")',
        filters: [Ruby2JS::Filter::TestMultiRewrite]).to_s
      _(js1).must_equal 'console.log("a")'

      js2 = Ruby2JS.convert('p("b")',
        filters: [Ruby2JS::Filter::TestMultiRewrite]).to_s
      _(js2).must_equal 'console.log("b")'
    end

    it "rewrites fall through to custom handler" do
      Ruby2JS.filter(:TestMixed) do
        rewrite 'puts(_1)', to: 'console.log(_1)'

        on_send do |node|
          _receiver, method, *_args = node.children
          if method == :warn
            s(:send, s(:lvar, :console), :warn, *_args)
          end
        end
      end

      js1 = Ruby2JS.convert('puts("a")',
        filters: [Ruby2JS::Filter::TestMixed]).to_s
      _(js1).must_equal 'console.log("a")'

      js2 = Ruby2JS.convert('warn("b")',
        filters: [Ruby2JS::Filter::TestMixed]).to_s
      _(js2).must_equal 'console.warn("b")'
    end
  end

  describe 'end-to-end: Writebook-style rewrites' do
    after do
      [:WritebookTest].each do |name|
        Ruby2JS::Filter.send(:remove_const, name) if Ruby2JS::Filter.const_defined?(name)
      end
    end

    it "stubs RQRCode with SVG string" do
      Ruby2JS.filter(:WritebookTest) do
        rewrite 'RQRCode::QRCode.new(_1).as_svg(_2)',
          to: '"<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>"'
      end

      js = Ruby2JS.convert('RQRCode::QRCode.new(url).as_svg(opts)',
        filters: [Ruby2JS::Filter::WritebookTest]).to_s
      _(js).must_include '<svg'
      _(js).must_include '</svg>'
    end
  end
end
