require 'minitest/autorun'
require 'ruby2js/filter/pragma'

describe Ruby2JS::Filter::Pragma do

  def to_js(string, options={})
    _(Ruby2JS.convert(string, options.merge(
      eslevel: options[:eslevel] || 2021,
      or: options[:or] || :logical,  # Use || by default so we can test pragma override to ??
      filters: [Ruby2JS::Filter::Pragma]
    )).to_s)
  end

  describe "nullish pragma (??)" do
    it "should convert || to ?? with pragma" do
      to_js('x = a || b # Pragma: ??').
        must_equal 'let x = a ?? b'
    end

    it "should convert ||= to ??= with pragma" do
      to_js('a ||= b # Pragma: ??').
        must_equal 'a ??= b'
    end

    it "should accept 'nullish' as pragma name" do
      to_js('x = a || b # Pragma: nullish').
        must_equal 'let x = a ?? b'
    end

    it "should not convert || without pragma" do
      to_js('x = a || b').
        must_equal 'let x = a || b'
    end

    it "should not convert ||= without pragma" do
      to_js('a ||= b').
        must_equal 'a ||= b'
    end

    it "should handle nested || with pragma" do
      to_js('x = a || b || c # Pragma: ??').
        must_equal 'let x = a ?? b ?? c'
    end

    it "should handle complex expressions with pragma" do
      to_js('x = foo.bar || default_value # Pragma: ??').
        must_equal 'let x = foo.bar ?? default_value'
    end

    it "should handle instance variable assignment with pragma" do
      to_js('@a ||= b # Pragma: ??').
        must_equal 'this._a ??= b'
    end

    it "should be case insensitive for pragma name" do
      to_js('x = a || b # PRAGMA: ??').
        must_equal 'let x = a ?? b'
    end

    it "should fall back to || when ES2020 not available" do
      # When ES2020 is not available, nullish_or pragma has no effect
      to_js('x = a || b # Pragma: ??', eslevel: 2019).
        must_equal 'let x = a || b'
    end

    it "should expand nullish assignment when ES2021 not available" do
      # ES2020 has ?? but not ??=, so it expands to a = a ?? b
      to_js('a ||= b # Pragma: ??', eslevel: 2020).
        must_equal 'a = a ?? b'
    end
  end

  describe "logical pragma (||)" do
    # These tests use or: :nullish to test pragma override from ?? back to ||
    def to_js_nullish(string, options={})
      _(Ruby2JS.convert(string, options.merge(
        eslevel: options[:eslevel] || 2021,
        or: :nullish,  # Use ?? by default so we can test pragma override to ||
        filters: [Ruby2JS::Filter::Pragma]
      )).to_s)
    end

    it "should force || with pragma when or: :nullish" do
      to_js_nullish('x = a || b # Pragma: logical').
        must_equal 'let x = a || b'
    end

    it "should force || with pragma when or: :nullish" do
      to_js_nullish('x = a || b # Pragma: ||').
        must_equal 'let x = a || b'
    end

    it "should force ||= with pragma when or: :nullish" do
      to_js_nullish('a ||= b # Pragma: logical').
        must_equal 'a ||= b'
    end

    it "should not force || without pragma when or: :nullish" do
      to_js_nullish('x = a || b').
        must_equal 'let x = a ?? b'
    end

    it "should handle boolean false correctly with logical pragma" do
      # This is the key use case: when variable can be false, ||= should stay as ||=
      to_js_nullish('x ||= true # Pragma: logical').
        must_equal 'x ||= true'
    end

    it "should expand logical assignment when ES2021 not available" do
      to_js_nullish('a ||= b # Pragma: logical', eslevel: 2020).
        must_equal 'a = a || b'
    end
  end

  describe "function pragma" do
    it "should force function syntax for blocks" do
      to_js('items.each { |item| process(item) } # Pragma: function').
        must_equal 'items.each(function(item) {process(item)})'
    end

    it "should accept 'noes2015' as legacy pragma name" do
      to_js('items.each { |item| process(item) } # Pragma: noes2015').
        must_equal 'items.each(function(item) {process(item)})'
    end

    it "should use arrow functions without pragma" do
      to_js('items.each { |item| process(item) }').
        must_equal 'items.each(item => process(item))'
    end

    it "should handle multi-argument blocks with pragma" do
      # Note: method name stays as each_with_index since functions filter not included
      to_js('items.each_with_index { |item, i| process(item, i) } # Pragma: noes2015').
        must_equal 'items.each_with_index(function(item, i) {process(item, i)})'
    end

    it "should handle blocks with multiple statements" do
      to_js("items.map { |x| y = x * 2; y + 1 } # Pragma: noes2015").
        must_include 'function(x)'
    end

    it "should preserve this binding with function syntax" do
      # This is the main use case - jQuery/DOM callbacks need 'this'
      js = to_js('element.on("click") { handle_click(this) } # Pragma: noes2015')
      js.must_include 'function()'
      js.must_include 'this'
    end
  end

  describe "guard pragma" do
    it "should guard splat array against null" do
      to_js('[*a] # Pragma: guard').
        must_equal '[...a ?? []]'
    end

    it "should guard splat in mixed array" do
      to_js('[1, *a, 2] # Pragma: guard').
        must_equal '[1, ...a ?? [], 2]'
    end

    it "should preserve array wrapper without pragma" do
      # [*a] in Ruby always creates a new array (shallow copy)
      to_js('[*a]').
        must_equal '[...a]'
    end

    it "should handle multiple splats with guard" do
      to_js('[*a, *b] # Pragma: guard').
        must_include 'a ?? []'
    end

    it "should handle method call splats with guard" do
      to_js('[*items.to_a] # Pragma: guard').
        must_include '?? []'
    end

    it "should not apply guard pragma without ES2020" do
      # Without ES2020, nullish coalescing isn't available, so guard has no effect
      # At ES2019 spread is available but ?? is not, so guard doesn't apply
      to_js('[1, *a] # Pragma: guard', eslevel: 2019).
        must_equal '[1, ...a]'
    end

  end

  describe "multiple pragmas" do
    it "should handle multiple pragmas on different lines" do
      code = <<~RUBY
        a ||= b # Pragma: ??
        items.each { |x| process(x) } # Pragma: noes2015
      RUBY
      js = to_js(code)
      js.must_include '??='
      js.must_include 'function(x)'
    end
  end

  describe "pragma syntax variations" do
    it "should handle extra whitespace" do
      to_js('x = a || b #   Pragma:   ??').
        must_equal 'let x = a ?? b'
    end

    it "should handle pragma at end of complex statement" do
      # Note: 'default' is a JS reserved word, so it gets escaped to '$default'
      to_js('result = foo.bar.baz || default_value # Pragma: ??').
        must_equal 'let result = foo.bar.baz ?? default_value'
    end

    it "should ignore unknown pragmas" do
      to_js('x = a || b # Pragma: unknown').
        must_equal 'let x = a || b'
    end
  end

  describe "array pragma" do
    it "should convert dup to slice" do
      to_js('x = arr.dup # Pragma: array').
        must_equal 'let x = arr.slice()'
    end

    it "should convert << to push" do
      to_js('arr << item # Pragma: array').
        must_equal 'arr.push(item)'
    end

    it "should convert += to push with spread" do
      to_js('arr += [1, 2] # Pragma: array').
        must_equal 'arr.push(...[1, 2])'
    end

    it "should convert += to push with inferred type" do
      to_js('arr = []; arr += [1, 2]').
        must_equal 'let arr = []; arr.push(...[1, 2])'
    end

    it "should convert + to spread concat with pragma" do
      to_js('x = a + b # Pragma: array').
        must_equal 'let x = [...a, ...b]'
    end

    it "should convert + to spread concat with inferred type" do
      to_js('a = [1]; x = a + [2, 3]').
        must_equal 'let a = [1]; let x = [...a, ...[2, 3]]'
    end

    it "should convert - to filter for difference with pragma" do
      to_js('x = a - b # Pragma: array').
        must_equal 'let x = a.filter(x => !b.includes(x))'
    end

    it "should convert - to filter for difference with inferred type" do
      to_js('a = [1, 2, 3]; x = a - [2]').
        must_equal 'let a = [1, 2, 3]; let x = a.filter(x => ![2].includes(x))'
    end

    it "should convert -= to filter assignment" do
      # Note: adds 'let' since arr wasn't declared before
      to_js('arr -= [1, 2] # Pragma: array').
        must_equal 'let arr = arr.filter(x => (![1, 2].includes(x)))'
    end

    it "should convert -= with inferred type" do
      to_js('arr = [1, 2, 3]; arr -= [2]').
        must_equal 'let arr = [1, 2, 3]; arr = arr.filter(x => ![2].includes(x))'
    end

    it "should convert & to filter for intersection with pragma" do
      to_js('x = a & b # Pragma: array').
        must_equal 'let x = a.filter(x => b.includes(x))'
    end

    it "should convert & to filter for intersection with inferred type" do
      to_js('a = [1, 2, 3]; x = a & [2, 3, 4]').
        must_equal 'let a = [1, 2, 3]; let x = a.filter(x => ([2, 3, 4].includes(x)))'
    end

    it "should convert &= to filter assignment" do
      # Note: adds 'let' since arr wasn't declared before
      to_js('arr &= [1, 2] # Pragma: array').
        must_equal 'let arr = arr.filter(x => ([1, 2].includes(x)))'
    end

    it "should convert &= with inferred type" do
      to_js('arr = [1, 2, 3]; arr &= [2, 3]').
        must_equal 'let arr = [1, 2, 3]; arr = arr.filter(x => ([2, 3].includes(x)))'
    end

    it "should convert | to Set spread for union with pragma" do
      to_js('x = a | b # Pragma: array').
        must_equal 'let x = [...new Set([...a, ...b])]'
    end

    it "should convert | to Set spread for union with inferred type" do
      to_js('a = [1, 2]; x = a | [2, 3]').
        must_equal 'let a = [1, 2]; let x = [...new Set([...a, ...[2, 3]])]'
    end

    it "should convert |= to Set spread assignment" do
      # Note: adds 'let' since arr wasn't declared before
      to_js('arr |= [1, 2] # Pragma: array').
        must_equal 'let arr = [...new Set([...arr, ...[1, 2]])]'
    end

    it "should convert |= with inferred type" do
      to_js('arr = [1, 2]; arr |= [2, 3]').
        must_equal 'let arr = [1, 2]; arr = [...new Set([...arr, ...[2, 3]])]'
    end

    it "should not affect + without array type" do
      to_js('x = a + b').
        must_equal 'let x = a + b'
    end

    it "should not affect - without array type" do
      to_js('x = a - b').
        must_equal 'let x = a - b'
    end

    it "should not affect dup without pragma" do
      to_js('x = arr.dup').
        must_equal 'let x = arr.dup'
    end
  end

  describe "hash pragma" do
    it "should convert dup to spread" do
      to_js('x = obj.dup # Pragma: hash').
        must_equal 'let x = {...obj}'
    end

    it "should convert include? to in operator" do
      to_js('obj.include?(key) # Pragma: hash').
        must_equal 'key in obj'
    end

    it "should not affect include? without pragma" do
      # Without functions filter, include? stays as is
      to_js('obj.include?(key)').
        must_equal 'obj.include(key)'
    end

    it "should convert any? to Object.keys check" do
      to_js('obj.any? # Pragma: hash').
        must_equal 'Object.keys(obj).length > 0'
    end

    it "should convert empty? to Object.keys check" do
      to_js('obj.empty? # Pragma: hash').
        must_equal 'Object.keys(obj).length === 0'
    end
  end

  describe "set pragma" do
    it "should convert << to add" do
      to_js('s << item # Pragma: set').
        must_equal 's.add(item)'
    end

    it "should convert include? to has" do
      to_js('s.include?(item) # Pragma: set').
        must_equal 's.has(item)'
    end

    it "should not affect << without pragma" do
      # Without pragma, << becomes push (array default)
      to_js('s << item').
        must_equal 's.push(item)'
    end

    it "should keep delete as method call" do
      require 'ruby2js/filter/functions'
      # Without pragma, delete becomes delete keyword (hash default)
      # With set pragma, keep as method call for Set/Map
      _(Ruby2JS.convert('s.delete(item) # Pragma: set',
        eslevel: 2021,
        filters: [Ruby2JS::Filter::Pragma, Ruby2JS::Filter::Functions]
      ).to_s).must_equal 's.delete(item)'
    end

    it "should not affect delete without pragma" do
      require 'ruby2js/filter/functions'
      # Without pragma, delete becomes delete keyword (hash default)
      _(Ruby2JS.convert('h.delete(key)',
        eslevel: 2021,
        filters: [Ruby2JS::Filter::Pragma, Ruby2JS::Filter::Functions]
      ).to_s).must_equal 'delete h[key]'
    end
  end

  describe "string pragma" do
    it "should convert dup to no-op" do
      to_js('x = str.dup # Pragma: string').
        must_equal 'let x = str'
    end
  end

  describe "method pragma" do
    it "should convert proc.call to direct invocation" do
      to_js('fn.call(x) # Pragma: method').
        must_equal 'fn(x)'
    end

    it "should handle call with multiple arguments" do
      to_js('fn.call(a, b, c) # Pragma: method').
        must_equal 'fn(a, b, c)'
    end

    it "should not affect call without pragma" do
      to_js('fn.call(x)').
        must_equal 'fn.call(x)'
    end
  end

  describe "proto pragma" do
    it "should convert .class to .constructor" do
      to_js('obj.class # Pragma: proto').
        must_equal 'obj.constructor'
    end

    it "should not affect .class without pragma" do
      to_js('obj.class').
        must_equal 'obj.class'
    end
  end

  describe "entries pragma" do
    it "should convert hash.each with two args to Object.entries" do
      to_js('hash.each { |k, v| puts k } # Pragma: entries').
        must_include 'Object.entries(hash)'
    end

    it "should convert each_pair to Object.entries" do
      to_js('hash.each_pair { |k, v| puts k } # Pragma: entries').
        must_include 'Object.entries(hash)'
    end

    it "should not affect each without pragma" do
      to_js('hash.each { |k, v| puts k }').
        must_include 'hash.each'
    end
  end

  describe "skip pragma" do
    it "should remove require with skip pragma" do
      to_js("require 'prism' # Pragma: skip").
        wont_include 'require'
    end

    it "should remove require_relative with skip pragma" do
      to_js("require_relative 'other' # Pragma: skip").
        wont_include 'require'
    end

    it "should not affect require without pragma" do
      to_js("require 'something'").
        must_include 'require'
    end

    it "should handle skip with other statements" do
      code = <<~RUBY
        require 'external' # Pragma: skip
        puts 'hello'
      RUBY
      js = to_js(code)
      js.wont_include 'require'
      js.must_include 'puts'
    end

    it "should remove method definition with skip pragma" do
      code = <<~RUBY
        def respond_to?(method) # Pragma: skip
          true
        end
        def foo
          1
        end
      RUBY
      js = to_js(code)
      js.wont_include 'respond_to'
      js.must_include 'foo'
    end

    it "should remove class method with skip pragma" do
      code = <<~RUBY
        class Foo
          def self.===(other) # Pragma: skip
            true
          end
          def self.create
            42
          end
        end
      RUBY
      js = to_js(code)
      js.wont_include '==='
      js.must_include 'create'
    end

    it "should remove alias with skip pragma" do
      code = <<~RUBY
        class Foo
          alias loc location # Pragma: skip
          alias name title
        end
      RUBY
      js = to_js(code)
      js.wont_include 'loc'
      js.must_include 'name'
    end

    it "should not leave empty semicolons when skipping" do
      code = <<~RUBY
        require 'json' # Pragma: skip
        require 'yaml' # Pragma: skip
        x = 1
      RUBY
      js = to_js(code)
      js.wont_match(/^;/)
      js.wont_match(/;\s*;/)
      js.must_equal 'let x = 1'
    end

    it "should not leave empty semicolons for skipped methods" do
      code = <<~RUBY
        def skip_me # Pragma: skip
          true
        end
        def keep_me
          false
        end
      RUBY
      js = to_js(code)
      js.wont_match(/^;/)
      js.must_include 'keep_me'
      js.wont_include 'skip_me'
    end

    it "should skip if blocks with pragma" do
      code = <<~RUBY
        if true # Pragma: skip
          x = 1
        end
        y = 2
      RUBY
      js = to_js(code)
      js.wont_include 'x'
      js.must_include 'y'
    end

    it "should skip unless blocks with pragma" do
      code = <<~RUBY
        unless defined?(RUBY2JS_SELFHOST) # Pragma: skip
          require 'parser/current'
        end
        x = 1
      RUBY
      js = to_js(code)
      js.wont_include 'RUBY2JS_SELFHOST'
      js.wont_include 'parser'
      js.must_include 'x'
    end

    it "should skip begin blocks with pragma" do
      code = <<~RUBY
        begin # Pragma: skip
          x = 1
        end
        y = 2
      RUBY
      js = to_js(code)
      js.wont_include 'x'
      js.must_include 'y'
    end

    it "should skip while loops with pragma" do
      code = <<~RUBY
        while true # Pragma: skip
          x = 1
        end
        y = 2
      RUBY
      js = to_js(code)
      js.wont_include 'while'
      js.must_include 'y'
    end

    it "should skip case statements with pragma" do
      code = <<~RUBY
        case x # Pragma: skip
        when 1
          puts "one"
        end
        y = 2
      RUBY
      js = to_js(code)
      js.wont_include 'switch'
      js.wont_include 'one'
      js.must_include 'y'
    end
  end

  describe "extend pragma" do
    it "should extend existing class with methods" do
      to_js('class F; def m(); end; end # Pragma: extend').
        must_equal 'F.prototype.m = function() {}'
    end

    it "should extend existing class with properties" do
      to_js('class F; def p; 1; end; end # Pragma: extend').
        must_equal 'Object.defineProperty(F.prototype, "p", ' +
          '{enumerable: true, configurable: true, get() {return 1}})'
    end

    it "should extend existing class with constructors" do
      to_js('class F; def initialize() {}; end; end # Pragma: extend').
        must_equal '[(F = function F() {{}}).prototype] = [F.prototype]'
    end

    it "should extend built-in classes" do
      to_js('class String; def blank?; strip.empty?; end; end # Pragma: extend').
        must_include 'String.prototype'
    end

    it "should not extend class without pragma" do
      to_js('class F; def m(); end; end').
        must_include 'class F'
    end
  end

  describe "multiple pragmas on same line" do
    it "should apply both logical and method pragmas" do
      # Both pragmas should work: logical forces ||, method converts .call to ()
      to_js('x ||= fn.call(y) # Pragma: logical # Pragma: method').
        must_equal 'x ||= fn(y)'
    end

    it "should apply pragmas regardless of order" do
      to_js('x ||= fn.call(y) # Pragma: method # Pragma: logical').
        must_equal 'x ||= fn(y)'
    end

    it "should apply entries and hash pragmas together" do
      code = 'result = options.select { |k, v| v > 0 }.keys() # Pragma: entries # Pragma: hash'
      js = to_js(code)
      js.must_include 'Object.entries'
      js.must_include 'Object.fromEntries'
      js.must_include '.keys()'
    end

    it "should apply nullish and method pragmas together" do
      to_js('x ||= fn.call(y) # Pragma: ?? # Pragma: method').
        must_equal 'x ??= fn(y)'
    end
  end

  describe "type inference" do
    def to_js_with_functions(string, options={})
      require 'ruby2js/filter/functions'
      _(Ruby2JS.convert(string, options.merge(
        eslevel: options[:eslevel] || 2021,
        filters: [Ruby2JS::Filter::Pragma, Ruby2JS::Filter::Functions]
      )).to_s)
    end

    describe "from literals" do
      it "should infer array type from []" do
        to_js('items = []; items << "x"').
          must_equal 'let items = []; items.push("x")'
      end

      it "should infer hash type from {}" do
        to_js('h = {}; h.empty?').
          must_equal 'let h = {}; Object.keys(h).length === 0'
      end

      it "should infer string type from string literal" do
        to_js('s = "hello"; s << " world"').
          must_equal 'let s = "hello"; s += " world"'
      end
    end

    describe "from constructor calls" do
      it "should infer set type from Set.new" do
        to_js('s = Set.new; s << "x"').
          must_equal 'let s = new Set; s.add("x")'
      end

      it "should infer map type from Map.new" do
        to_js('m = Map.new; m[:key] = "val"').
          must_equal 'let m = new Map; m.set("key", "val")'
      end

      it "should infer array type from Array.new" do
        to_js('a = Array.new; a << 1').
          must_equal 'let a = new Array; a.push(1)'
      end

      it "should infer hash type from Hash.new" do
        to_js('h = Hash.new; h.any?').
          must_equal 'let h = new Hash; Object.keys(h).length > 0'
      end
    end

    describe "instance variables" do
      it "should track types for instance variables" do
        to_js('@items = []; @items << "x"').
          must_equal 'this._items = []; this._items.push("x")'
      end

      it "should track set type for instance variables" do
        to_js('@s = Set.new; @s << "x"').
          must_equal 'this._s = new Set; this._s.add("x")'
      end
    end

    describe "disambiguation" do
      it "should disambiguate << for array vs set" do
        code = <<~RUBY
          arr = []
          arr << 1
          s = Set.new
          s << 2
        RUBY
        js = to_js(code)
        js.must_include 'arr.push(1)'
        js.must_include 's.add(2)'
      end

      it "should disambiguate .dup for array vs hash" do
        code = <<~RUBY
          arr = [1, 2]
          a2 = arr.dup
          h = {a: 1}
          h2 = h.dup
        RUBY
        js = to_js(code)
        js.must_include 'arr.slice()'
        js.must_include '{...h}'
      end

      it "should disambiguate .include? for set vs hash" do
        code = <<~RUBY
          s = Set.new
          s.include?("x")
          h = {}
          h.include?("y")
        RUBY
        js = to_js(code)
        js.must_include 's.has("x")'
        js.must_include '"y" in h'
      end

      it "should disambiguate .delete for set" do
        to_js_with_functions('s = Set.new; s.delete("x")').
          must_equal 'let s = new Set; s.delete("x")'
      end

      it "should disambiguate .clear for set" do
        to_js_with_functions('s = Set.new; s.clear').
          must_equal 'let s = new Set; s.clear()'
      end

      it "should disambiguate .empty? for set (uses .size not .length)" do
        to_js_with_functions('s = Set.new; s.empty?').
          must_equal 'let s = new Set; s.size == 0'
      end

      it "should disambiguate .empty? for map (uses .size not .length)" do
        to_js_with_functions('m = Map.new; m.empty?').
          must_equal 'let m = new Map; m.size == 0'
      end

      it "should disambiguate [] and []= for map" do
        code = <<~RUBY
          m = Map.new
          m[:key] = "val"
          x = m[:key]
        RUBY
        js = to_js(code)
        js.must_include 'm.set("key", "val")'
        js.must_include 'm.get("key")'
      end

      it "should disambiguate .key? for map" do
        to_js('m = Map.new; m.key?(:k)').
          must_equal 'let m = new Map; m.has("k")'
      end

      it "should disambiguate .any? and .empty? for hash" do
        code = <<~RUBY
          h = {}
          h.any?
          h.empty?
        RUBY
        js = to_js(code)
        js.must_include 'Object.keys(h).length > 0'
        js.must_include 'Object.keys(h).length === 0'
      end
    end

    describe "scope management" do
      it "should not leak types across method definitions" do
        code = <<~RUBY
          def foo
            items = Set.new
            items << "a"
          end
          def bar
            items << "b"
          end
        RUBY
        js = to_js(code)
        js.must_include 'items.add("a")'  # foo knows it's a Set
        js.must_include 'items.push("b")' # bar doesn't know, defaults to push
      end

      it "should not leak types across class definitions" do
        code = <<~RUBY
          class A
            def foo
              @items = Set.new
            end
          end
          class B
            def bar
              @items << "x"
            end
          end
        RUBY
        js = to_js(code)
        js.must_include 'this._items = new Set'
        js.must_include 'this._items.push("x")' # B doesn't know type
      end

      it "should track ivar types from initialize across methods" do
        code = <<~RUBY
          class Foo
            def initialize
              @items = Set.new
            end
            def add(x)
              @items << x
            end
          end
        RUBY
        js = to_js(code)
        js.must_include 'this._items = new Set'
        js.must_include 'this._items.add(x)' # knows it's a Set from initialize
      end

      it "should convert Set.select to array spread with filter" do
        code = <<~RUBY
          class Foo
            def initialize
              @items = Set.new
            end
            def filtered
              @items.select { |x| x > 0 }
            end
          end
        RUBY
        js = to_js(code)
        js.must_include '[...this._items].filter(x => x > 0)'
      end

      it "should preserve types within same method" do
        code = <<~RUBY
          def foo
            items = []
            if true
              items << 1
            end
            items << 2
          end
        RUBY
        js = to_js(code)
        js.must_include 'items.push(1)'
        js.must_include 'items.push(2)'
      end

      it "should allow type reassignment within method" do
        code = <<~RUBY
          def foo
            x = []
            x << 1
            x = Set.new
            x << 2
          end
        RUBY
        js = to_js(code)
        js.must_include 'x.push(1)'
        js.must_include 'x.add(2)'
      end
    end

    describe "shadowarg handling" do
      it "should preserve outer type when variable is shadowed" do
        code = <<~RUBY
          x = []
          [1].each do |i; x|
            x = Set.new
            x << i
          end
          x << 2
        RUBY
        js = to_js(code)
        js.must_include 'x.add(i)'  # inner x is Set
        js.must_include 'x.push(2)' # outer x is still Array
      end

      it "should handle shadowarg for variable not previously defined" do
        code = <<~RUBY
          [1].each do |i; x|
            x = Set.new
            x << i
          end
        RUBY
        js = to_js(code)
        js.must_include 'x.add(i)'
      end
    end

    describe "pragma override" do
      it "should allow pragma to override inferred type" do
        # Even though items is inferred as array, pragma forces set behavior
        to_js('items = []; items << "x" # Pragma: set').
          must_equal 'let items = []; items.add("x")'
      end
    end

    describe "Sorbet T.let support" do
      it "should strip T.let and use type for disambiguation" do
        to_js('x = T.let([], Array); x << "a"').
          must_equal 'let x = []; x.push("a")'
      end

      it "should handle T.let with Set type" do
        to_js('x = T.let(Set.new, Set); x << "a"').
          must_equal 'let x = new Set; x.add("a")'
      end

      it "should handle T.let with Hash type" do
        to_js('x = T.let({}, Hash); x.empty?').
          must_equal 'let x = {}; Object.keys(x).length === 0'
      end

      it "should handle T::Array generic" do
        to_js('x = T.let([], T::Array[String]); x << "a"').
          must_equal 'let x = []; x.push("a")'
      end

      it "should handle T::Hash generic" do
        to_js('x = T.let({}, T::Hash[Symbol, String]); x.empty?').
          must_equal 'let x = {}; Object.keys(x).length === 0'
      end

      it "should handle T::Set generic" do
        to_js('x = T.let(Set.new, T::Set[String]); x << "a"').
          must_equal 'let x = new Set; x.add("a")'
      end

      it "should work with instance variables" do
        code = <<~RUBY
          class Foo
            def initialize
              @items = T.let([], Array)
            end
            def add(x)
              @items << x
            end
          end
        RUBY
        js = to_js(code)
        js.must_include 'this._items = []'
        js.must_include 'this._items.push(x)'
      end

      it "should pass through unrecognized T.let types" do
        # If we don't recognize the type, just strip T.let wrapper
        to_js('x = T.let(foo, SomeUnknownType)').
          must_equal 'let x = T.let(foo, SomeUnknownType)'
      end

      it "should strip require 'sorbet-runtime'" do
        to_js("require 'sorbet-runtime'; x = T.let([], Array); x << 'a'").
          must_equal "let x = []; x.push(\"a\")"
      end
    end
  end

  describe "target pragmas" do
    def to_js_with_target(string, target, options={})
      _(Ruby2JS.convert(string, options.merge(
        eslevel: options[:eslevel] || 2021,
        target: target,
        filters: [Ruby2JS::Filter::Pragma]
      )).to_s)
    end

    describe "browser target" do
      it "should include import with browser pragma when target is browser" do
        to_js_with_target("import 'reactflow/dist/style.css' # Pragma: browser", 'browser').
          must_include 'reactflow'
      end

      it "should skip import with browser pragma when target is node" do
        to_js_with_target("import 'reactflow/dist/style.css' # Pragma: browser", 'node').
          wont_include 'reactflow'
      end

      it "should skip import with browser pragma when target is capacitor" do
        to_js_with_target("import 'reactflow/dist/style.css' # Pragma: browser", 'capacitor').
          wont_include 'reactflow'
      end
    end

    describe "capacitor target" do
      it "should include import with capacitor pragma when target is capacitor" do
        to_js_with_target("import '@capacitor/camera' # Pragma: capacitor", 'capacitor').
          must_include '@capacitor/camera'
      end

      it "should skip import with capacitor pragma when target is browser" do
        to_js_with_target("import '@capacitor/camera' # Pragma: capacitor", 'browser').
          wont_include '@capacitor/camera'
      end

      it "should skip import with capacitor pragma when target is node" do
        to_js_with_target("import '@capacitor/camera' # Pragma: capacitor", 'node').
          wont_include '@capacitor/camera'
      end
    end

    describe "server target" do
      it "should include import with server pragma when target is node" do
        to_js_with_target("import 'pg' # Pragma: server", 'node').
          must_include 'pg'
      end

      it "should include import with server pragma when target is bun" do
        to_js_with_target("import 'pg' # Pragma: server", 'bun').
          must_include 'pg'
      end

      it "should include import with server pragma when target is deno" do
        to_js_with_target("import 'pg' # Pragma: server", 'deno').
          must_include 'pg'
      end

      it "should include import with server pragma when target is cloudflare" do
        to_js_with_target("import 'pg' # Pragma: server", 'cloudflare').
          must_include 'pg'
      end

      it "should include import with server pragma when target is vercel" do
        to_js_with_target("import 'pg' # Pragma: server", 'vercel').
          must_include 'pg'
      end

      it "should include import with server pragma when target is fly" do
        to_js_with_target("import 'pg' # Pragma: server", 'fly').
          must_include 'pg'
      end

      it "should skip import with server pragma when target is browser" do
        to_js_with_target("import 'pg' # Pragma: server", 'browser').
          wont_include 'pg'
      end

      it "should skip import with server pragma when target is capacitor" do
        to_js_with_target("import 'pg' # Pragma: server", 'capacitor').
          wont_include 'pg'
      end
    end

    describe "node target" do
      it "should include import with node pragma when target is node" do
        to_js_with_target("import 'fs' # Pragma: node", 'node').
          must_include 'fs'
      end

      it "should skip import with node pragma when target is browser" do
        to_js_with_target("import 'fs' # Pragma: node", 'browser').
          wont_include 'fs'
      end

      it "should skip import with node pragma when target is bun" do
        to_js_with_target("import 'fs' # Pragma: node", 'bun').
          wont_include 'fs'
      end
    end

    describe "cloudflare target" do
      it "should include import with cloudflare pragma when target is cloudflare" do
        to_js_with_target("import '@cloudflare/workers-types' # Pragma: cloudflare", 'cloudflare').
          must_include '@cloudflare/workers-types'
      end

      it "should skip import with cloudflare pragma when target is node" do
        to_js_with_target("import '@cloudflare/workers-types' # Pragma: cloudflare", 'node').
          wont_include '@cloudflare/workers-types'
      end
    end

    describe "vercel target" do
      it "should include import with vercel pragma when target is vercel" do
        to_js_with_target("import '@vercel/og' # Pragma: vercel", 'vercel').
          must_include '@vercel/og'
      end

      it "should skip import with vercel pragma when target is browser" do
        to_js_with_target("import '@vercel/og' # Pragma: vercel", 'browser').
          wont_include '@vercel/og'
      end
    end

    describe "electron target" do
      it "should include import with electron pragma when target is electron" do
        to_js_with_target("import 'electron' # Pragma: electron", 'electron').
          must_include 'electron'
      end

      it "should skip import with electron pragma when target is browser" do
        to_js_with_target("import 'electron' # Pragma: electron", 'browser').
          wont_include 'electron'
      end
    end

    describe "tauri target" do
      it "should include import with tauri pragma when target is tauri" do
        to_js_with_target("import '@tauri-apps/api' # Pragma: tauri", 'tauri').
          must_include '@tauri-apps/api'
      end

      it "should skip import with tauri pragma when target is browser" do
        to_js_with_target("import '@tauri-apps/api' # Pragma: tauri", 'browser').
          wont_include '@tauri-apps/api'
      end
    end

    describe "no target specified" do
      it "should include all imports when no target is set" do
        # When no target is set, include everything
        to_js("import '@capacitor/camera' # Pragma: capacitor").
          must_include '@capacitor/camera'
      end

      it "should include browser-only imports when no target is set" do
        to_js("import 'reactflow/dist/style.css' # Pragma: browser").
          must_include 'reactflow'
      end

      it "should include server-only imports when no target is set" do
        to_js("import 'pg' # Pragma: server").
          must_include 'pg'
      end
    end

    describe "require and require_relative" do
      it "should skip require with target pragma when target doesn't match" do
        to_js_with_target("require 'pg' # Pragma: server", 'browser').
          wont_include 'pg'
      end

      it "should include require with target pragma when target matches" do
        to_js_with_target("require 'pg' # Pragma: server", 'node').
          must_include 'pg'
      end

      it "should skip require_relative with target pragma when target doesn't match" do
        to_js_with_target("require_relative 'server_utils' # Pragma: node", 'browser').
          wont_include 'server_utils'
      end

      it "should include require_relative with target pragma when target matches" do
        to_js_with_target("require_relative 'server_utils' # Pragma: node", 'node').
          must_include 'server_utils'
      end
    end

    describe "multiple imports with different targets" do
      it "should selectively include imports based on target" do
        code = <<~RUBY
          import 'reactflow/dist/style.css' # Pragma: browser
          import '@capacitor/camera' # Pragma: capacitor
          import 'common-utils'
        RUBY

        # Browser target: include browser and common, skip capacitor
        js_browser = to_js_with_target(code, 'browser')
        js_browser.must_include 'reactflow'
        js_browser.wont_include '@capacitor/camera'
        js_browser.must_include 'common-utils'

        # Capacitor target: include capacitor and common, skip browser
        js_capacitor = to_js_with_target(code, 'capacitor')
        js_capacitor.wont_include 'reactflow'
        js_capacitor.must_include '@capacitor/camera'
        js_capacitor.must_include 'common-utils'
      end
    end

    describe "case insensitivity" do
      it "should handle uppercase pragma names" do
        to_js_with_target("import 'reactflow' # Pragma: BROWSER", 'browser').
          must_include 'reactflow'
      end

      it "should handle mixed case pragma names" do
        to_js_with_target("import 'reactflow' # Pragma: Browser", 'browser').
          must_include 'reactflow'
      end
    end

    describe "combined with skip pragma" do
      it "should skip import with skip pragma regardless of target" do
        to_js_with_target("import 'skip-me' # Pragma: skip", 'browser').
          wont_include 'skip-me'
      end

      it "should handle both skip and target pragmas" do
        # Skip takes precedence
        to_js_with_target("import 'skip-me' # Pragma: browser # Pragma: skip", 'browser').
          wont_include 'skip-me'
      end
    end
  end

  describe "pragma filter reorder" do
    it "should position pragma first in filter list" do
      require 'ruby2js/filter/require'
      require 'ruby2js/filter/functions'
      require 'ruby2js/filter/esm'

      filters = [
        Ruby2JS::Filter::Require,
        Ruby2JS::Filter::Functions,
        Ruby2JS::Filter::Pragma,
        Ruby2JS::Filter::ESM
      ]

      reordered = Ruby2JS::Filter::Pragma.reorder(filters)

      # Pragma should be first so it has highest method resolution priority
      pragma_idx = reordered.index(Ruby2JS::Filter::Pragma)
      _(pragma_idx).must_equal 0
    end

    it "should work with pragmas in inlined files" do
      require 'ruby2js/filter/require'
      require 'ruby2js/filter/functions'
      require 'fileutils'

      # Create temp files
      Dir.mktmpdir do |dir|
        # Main file that requires helper
        File.write("#{dir}/main.rb", "require_relative 'helper'")

        # Helper file with pragma
        File.write("#{dir}/helper.rb", "x = obj.dup # Pragma: hash")

        js = Ruby2JS.convert(File.read("#{dir}/main.rb"),
          eslevel: 2021,
          file: "#{dir}/main.rb",
          filters: [
            Ruby2JS::Filter::Pragma,
            Ruby2JS::Filter::Require,
            Ruby2JS::Filter::Functions
          ]
        ).to_s

        # Pragma should be applied to inlined file
        _(js).must_include '{...obj}'
        _(js).wont_include 'obj.dup'
      end
    end
  end
end
