gem 'minitest'
require 'minitest/autorun'
require 'json'
require 'ruby2js'
require 'ruby2js/filter/require'
require 'ruby2js/filter/combiner'
require 'ruby2js/filter/pragma'
require 'ruby2js/filter/selfhost'
require 'ruby2js/filter/functions'
require 'ruby2js/filter/esm'
require 'tempfile'

describe "Selfhost Walker Transpilation" do
  def transpile_walker
    source = File.read(File.expand_path('../../lib/ruby2js/prism_walker.rb', __FILE__))
    Ruby2JS.convert(source,
      eslevel: 2022,
      underscored_private: true,
      file: File.expand_path('../../lib/ruby2js/prism_walker.rb', __FILE__),
      filters: [
        Ruby2JS::Filter::Pragma,
        Ruby2JS::Filter::Require,
        Ruby2JS::Filter::Combiner,
        Ruby2JS::Filter::Selfhost::Core,
        Ruby2JS::Filter::Selfhost::Walker,
        Ruby2JS::Filter::Functions,
        Ruby2JS::Filter::ESM
      ]
    ).to_s
  end

  def run_node(js_code)
    Tempfile.create(['walker_test', '.js']) do |f|
      f.write(js_code)
      f.flush
      result = `node #{f.path} 2>&1`
      raise "Node.js error: #{result}" unless $?.success?
      result.strip
    end
  end

  describe "syntax validation" do
    it "produces valid JavaScript" do
      js = transpile_walker
      Tempfile.create(['walker', '.js']) do |f|
        f.write(js)
        f.flush
        result = `node --check #{f.path} 2>&1`
        _(result).must_equal ''
        _($?.success?).must_equal true
      end
    end
  end

  describe "structure" do
    before do
      @js = transpile_walker
    end

    it "exports Ruby2JS module" do
      _(@js).must_include 'Ruby2JS = '
    end

    it "contains Node class" do
      _(@js).must_include 'class Node'
    end

    it "contains PrismWalker class" do
      _(@js).must_include 'class PrismWalker'
    end

    it "PrismWalker extends Prism.Visitor" do
      _(@js).must_include 'extends Prism.Visitor'
    end

    it "contains visitor methods" do
      _(@js).must_include 'visit_integer_node'
      _(@js).must_include 'visit_string_node'
      _(@js).must_include 'visit_call_node'
      _(@js).must_include 'visit_def_node'
      _(@js).must_include 'visit_class_node'
    end

    it "contains helper location classes" do
      _(@js).must_include 'class SimpleLocation'
      _(@js).must_include 'class SendLocation'
      _(@js).must_include 'class DefLocation'
    end
  end

  describe "Node class functionality" do
    it "can create and use Node instances" do
      js = transpile_walker
      test_code = <<~JS
        // Mock Prism.Visitor (needed for class definition)
        globalThis.Prism = { Visitor: class {} };

        #{js}

        // Test Node class
        const { Node } = Ruby2JS;

        // Create a simple node
        const node = new Node('int', [42]);
        console.log(JSON.stringify({
          type: node.type,
          children: node.children,
          hasLocation: node.location !== undefined
        }));
      JS

      result = run_node(test_code)
      data = JSON.parse(result)
      _(data['type']).must_equal 'int'
      _(data['children']).must_equal [42]
    end

    it "Node.updated creates new node with changes" do
      js = transpile_walker
      test_code = <<~JS
        // Mock Prism.Visitor (needed for class definition)
        globalThis.Prism = { Visitor: class {} };

        #{js}

        const { Node } = Ruby2JS;
        const node = new Node('int', [42]);
        const updated = node.updated('float', [3.14]);
        console.log(JSON.stringify({
          originalType: node.type,
          updatedType: updated.type,
          updatedChildren: updated.children
        }));
      JS

      result = run_node(test_code)
      data = JSON.parse(result)
      _(data['originalType']).must_equal 'int'
      _(data['updatedType']).must_equal 'float'
      _(data['updatedChildren']).must_equal [3.14]
    end
  end

  describe "PrismWalker instantiation" do
    it "can instantiate PrismWalker with mock Prism.Visitor" do
      js = transpile_walker
      test_code = <<~JS
        // Mock Prism.Visitor base class
        globalThis.Prism = {
          Visitor: class {
            visit(node) { return null; }
          }
        };
        // Mock PrismSourceBuffer (external dependency)
        globalThis.PrismSourceBuffer = class {
          constructor(source, file) {
            this.source = source;
            this.file = file;
          }
        };

        #{js}

        const { PrismWalker, Node } = Ruby2JS;

        // Create walker instance
        const walker = new PrismWalker('x = 1', 'test.rb');

        console.log(JSON.stringify({
          hasSource: typeof walker.source === 'string',
          hasFile: walker.file === 'test.rb',
          hasSMethod: typeof walker.s === 'function',
          hasSlMethod: typeof walker.sl === 'function'
        }));
      JS

      result = run_node(test_code)
      data = JSON.parse(result)
      _(data['hasSource']).must_equal true
      _(data['hasFile']).must_equal true
      _(data['hasSMethod']).must_equal true
      _(data['hasSlMethod']).must_equal true
    end

    it "walker.s() creates Node instances" do
      js = transpile_walker
      test_code = <<~JS
        globalThis.Prism = {
          Visitor: class {
            visit(node) { return null; }
          }
        };
        globalThis.PrismSourceBuffer = class {
          constructor(source, file) {
            this.source = source;
            this.file = file;
          }
        };

        #{js}

        const { PrismWalker, Node } = Ruby2JS;
        const walker = new PrismWalker('test', null);

        // Use s() helper to create node
        const node = walker.s('send', null, 'puts', walker.s('str', 'hello'));

        console.log(JSON.stringify({
          type: node.type,
          childCount: node.children.length,
          isNode: node instanceof Node
        }));
      JS

      result = run_node(test_code)
      data = JSON.parse(result)
      _(data['type']).must_equal 'send'
      _(data['childCount']).must_equal 3
      _(data['isNode']).must_equal true
    end
  end

  describe "visitor methods exist" do
    before do
      @js = transpile_walker
    end

    # Smoke test: check that key visitor methods are present
    %w[
      visit_integer_node
      visit_float_node
      visit_string_node
      visit_symbol_node
      visit_nil_node
      visit_true_node
      visit_false_node
      visit_array_node
      visit_hash_node
      visit_call_node
      visit_local_variable_read_node
      visit_local_variable_write_node
      visit_instance_variable_read_node
      visit_def_node
      visit_class_node
      visit_module_node
      visit_if_node
      visit_while_node
      visit_block_node
      visit_lambda_node
    ].each do |method|
      it "has #{method}" do
        _(@js).must_include "#{method}(node)"
      end
    end
  end
end
