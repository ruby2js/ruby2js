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

    it "should convert delete to splice with pragma" do
      to_js('arr.delete(val) # Pragma: array').
        must_equal 'arr.splice(arr.indexOf(val), 1)'
    end

    it "should convert delete to splice with inferred type" do
      to_js('arr = [1, 2, 3]; arr.delete(2)').
        must_equal 'let arr = [1, 2, 3]; arr.splice(arr.indexOf(2), 1)'
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

    it "should convert clear to delete loop" do
      to_js('obj.clear # Pragma: hash').
        must_include 'Object.keys(obj)'
    end

    it "should convert first to Object.entries[0]" do
      to_js('obj.first # Pragma: hash').
        must_equal 'Object.entries(obj)[0]'
    end

    it "should convert to_h to no-op" do
      to_js('h = {}; h.to_h # Pragma: hash').
        must_equal 'let h = {}; h'
    end

    it "should convert compact to fromEntries/filter" do
      to_js('obj.compact # Pragma: hash').
        must_include 'Object.fromEntries'
    end

    it "should convert flatten to entries.flat" do
      to_js('obj.flatten # Pragma: hash').
        must_include 'Object.entries(obj).flat(Infinity)'
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

    it "should convert merge to for/add loop via type inference" do
      require 'ruby2js/filter/functions'
      _(Ruby2JS.convert('s = Set.new; s.merge(items)',
        eslevel: 2021,
        filters: [Ruby2JS::Filter::Pragma, Ruby2JS::Filter::Functions]
      ).to_s).must_equal 'let s = new Set; for (let _item of items) {s.add(_item)}'
    end
  end

  describe "string pragma" do
    it "should convert dup to no-op" do
      to_js('x = str.dup # Pragma: string').
        must_equal 'let x = str'
    end

    it "should convert replace to reassignment for lvar" do
      to_js('s = "hello"; s.replace("world") # Pragma: string').
        must_equal 'let s = "hello"; s = "world"'
    end

    it "should convert replace to reassignment with inferred type" do
      to_js('s = "hello"; s.replace("world")').
        must_equal 'let s = "hello"; s = "world"'
    end

    it "should convert replace for ivar" do
      to_js('@s = "hello"; @s.replace("world") # Pragma: string').
        must_equal 'this._s = "hello"; this._s = "world"'
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

    it "should apply entries pragma to reduce on hash" do
      to_js('hash.reduce(0) { |acc, (k, v)| acc + v } # Pragma: entries').
        must_include 'Object.entries(hash).reduce'
    end

    it "should apply entries pragma to flat_map on hash" do
      to_js('hash.flat_map { |k, v| [k, v] } # Pragma: entries').
        must_include 'Object.entries(hash)'
    end

    it "should apply entries pragma to each_with_index on hash" do
      to_js('hash.each_with_index { |(k, v), i| puts i } # Pragma: entries').
        must_include 'Object.entries(hash)'
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

    describe "from proc/lambda" do
      it "should infer proc type from proc { }" do
        to_js('fn = proc { |x| x + 1 }; fn[5]').
          must_equal 'let fn = x => x + 1; fn(5)'
      end

      it "should infer proc type from lambda { }" do
        to_js('fn = lambda { |x| x * 2 }; fn[10]').
          must_equal 'let fn = x => x * 2; fn(10)'
      end

      it "should convert proc[] with multiple arguments" do
        to_js('fn = proc { |a, b| a + b }; fn[1, 2]').
          must_equal 'let fn = (a, b) => a + b; fn(1, 2)'
      end

      it "should not affect regular array access" do
        to_js('arr = [1, 2, 3]; arr[0]').
          must_equal 'let arr = [1, 2, 3]; arr[0]'
      end

      it "should not affect unknown variable bracket access" do
        to_js('def test(fn); fn[1]; end').
          must_include 'fn[1]'
      end

      it "should handle proc reassignment" do
        to_js('x = proc { 1 }; x[]; x = [1]; x[0]').
          must_equal 'let x = () => 1; x(); x = [1]; x[0]'
      end
    end

    describe "from group_by" do
      it "should infer hash type from group_by result" do
        to_js_with_functions(
          'scores.group_by { |s| s.heat_id }.map { |k, v| [k, v.length] }'
        ).must_include 'Object.entries('
      end

      it "should wrap group_by + select in Object.entries and fromEntries" do
        to_js_with_functions(
          'scores.group_by { |s| s.heat_id }.select { |k, v| v.length > 1 }'
        ).must_include 'Object.fromEntries(Object.entries('
      end

      it "should wrap group_by + each in Object.entries" do
        to_js_with_functions(
          'scores.group_by { |s| s.id }.each { |k, v| puts k }'
        ).must_include 'Object.entries('
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

      it "should disambiguate .delete for array" do
        to_js_with_functions('a = [1, 2, 3]; a.delete(2)').
          must_equal 'let a = [1, 2, 3]; a.splice(a.indexOf(2), 1)'
      end

      it "should disambiguate .clear for hash" do
        to_js_with_functions('h = {}; h.clear').
          must_include 'Object.keys(h)'
      end

      it "should disambiguate .first for hash" do
        to_js('h = {}; h.first').
          must_equal 'let h = {}; Object.entries(h)[0]'
      end

      it "should disambiguate .to_h for hash" do
        to_js('h = {}; h.to_h').
          must_equal 'let h = {}; h'
      end

      it "should disambiguate .compact for hash" do
        to_js('h = {}; h.compact').
          must_include 'Object.fromEntries'
      end

      it "should disambiguate .flatten for hash" do
        to_js('h = {}; h.flatten').
          must_include 'Object.entries(h).flat(Infinity)'
      end

      it "should disambiguate .replace for string" do
        to_js('s = "hello"; s.replace("world")').
          must_equal 'let s = "hello"; s = "world"'
      end

      it "should disambiguate reduce for hash" do
        to_js_with_functions('h = {}; h.reduce(0) { |acc, (k, v)| acc + v }').
          must_include 'Object.entries(h).reduce'
      end

      it "should disambiguate flat_map for hash" do
        to_js_with_functions('h = {}; h.flat_map { |k, v| [k, v] }').
          must_include 'Object.entries(h).flatMap'
      end

      it "should disambiguate each_with_index for hash" do
        to_js_with_functions('h = {}; h.each_with_index { |(k, v), i| puts i }').
          must_include 'Object.entries(h).forEach'
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

  describe "lint mode diagnostics" do
    def lint(string, options={})
      diagnostics = []
      Ruby2JS.convert(string, options.merge(
        eslevel: options[:eslevel] || 2021,
        filters: [Ruby2JS::Filter::Pragma],
        lint: true,
        diagnostics: diagnostics
      ))
      diagnostics
    end

    it "should report ambiguous delete without type info" do
      diags = lint('obj.delete(key)')
      _(diags.length).must_be :>=, 1
      d = diags.find { |d| d[:rule] == :ambiguous_method && d[:method] == 'delete' }
      _(d).wont_be_nil
      _(d[:severity]).must_equal :warning
      _(d[:valid_types]).must_include :set
      _(d[:valid_types]).must_include :array
    end

    it "should be silent when pragma is present" do
      diags = lint('obj.delete(key) # Pragma: set')
      ambiguous = diags.select { |d| d[:rule] == :ambiguous_method }
      _(ambiguous).must_be_empty
    end

    it "should be silent when type is inferred" do
      diags = lint('x = []; x.delete(1)')
      ambiguous = diags.select { |d| d[:rule] == :ambiguous_method && d[:method] == 'delete' }
      _(ambiguous).must_be_empty
    end

    it "should report ambiguous <<" do
      diags = lint('obj << item')
      d = diags.find { |d| d[:rule] == :ambiguous_method && d[:method] == '<<' }
      _(d).wont_be_nil
      _(d[:valid_types]).must_include :array
      _(d[:valid_types]).must_include :set
      _(d[:valid_types]).must_include :string
    end

    it "should report ambiguous include?" do
      diags = lint('obj.include?(key)')
      d = diags.find { |d| d[:rule] == :ambiguous_method && d[:method] == 'include?' }
      _(d).wont_be_nil
      _(d[:valid_types]).must_include :hash
      _(d[:valid_types]).must_include :set
    end

    it "should report ambiguous dup" do
      diags = lint('obj.dup')
      d = diags.find { |d| d[:rule] == :ambiguous_method && d[:method] == 'dup' }
      _(d).wont_be_nil
      _(d[:valid_types]).must_include :array
      _(d[:valid_types]).must_include :hash
      _(d[:valid_types]).must_include :string
    end

    it "should report ambiguous empty?" do
      diags = lint('obj.empty?')
      d = diags.find { |d| d[:rule] == :ambiguous_method && d[:method] == 'empty?' }
      _(d).wont_be_nil
      _(d[:valid_types]).must_include :hash
      _(d[:valid_types]).must_include :set
      _(d[:valid_types]).must_include :map
    end

    it "should include valid_types in diagnostic" do
      diags = lint('obj.clear')
      d = diags.find { |d| d[:rule] == :ambiguous_method && d[:method] == 'clear' }
      _(d).wont_be_nil
      _(d[:valid_types].length).must_be :>=, 2
    end

    it "should not produce diagnostics when lint is not set" do
      diagnostics = []
      Ruby2JS.convert('obj.delete(key)',
        eslevel: 2021,
        filters: [Ruby2JS::Filter::Pragma],
        diagnostics: diagnostics
        # lint: true is NOT set
      )
      _(diagnostics).must_be_empty
    end

    it "should not produce diagnostics for non-ambiguous methods" do
      diags = lint('obj.to_s')
      ambiguous = diags.select { |d| d[:rule] == :ambiguous_method }
      _(ambiguous).must_be_empty
    end

    it "should not produce diagnostics for bare method calls" do
      diags = lint('delete "foo"')
      ambiguous = diags.select { |d| d[:rule] == :ambiguous_method && d[:method] == 'delete' }
      _(ambiguous).must_be_empty
    end

    it "should include line number in diagnostic" do
      diags = lint("x = 1\nobj.dup")
      d = diags.find { |d| d[:rule] == :ambiguous_method && d[:method] == 'dup' }
      _(d).wont_be_nil
      _(d[:line]).must_equal 2
    end

    it "should report ambiguous hash iteration with 2+ block args" do
      diags = lint('obj.each { |k, v| puts k }')
      d = diags.find { |d| d[:rule] == :ambiguous_method && d[:method] == 'each' }
      _(d).wont_be_nil
      _(d[:valid_types]).must_include :hash
    end

    it "should not report hash iteration when type is known" do
      diags = lint('h = {}; h.each { |k, v| puts k }')
      ambiguous = diags.select { |d| d[:rule] == :ambiguous_method && d[:method] == 'each' }
      _(ambiguous).must_be_empty
    end

    it "should not report strict-only warnings by default" do
      diags = lint('obj[key]')
      ambiguous = diags.select { |d| d[:rule] == :ambiguous_method && d[:method] == '[]' }
      _(ambiguous).must_be_empty
    end

    it "should report strict-only warnings when strict is set" do
      diags = lint('obj[key]', strict: true)
      d = diags.find { |d| d[:rule] == :ambiguous_method && d[:method] == '[]' }
      _(d).wont_be_nil
      _(d[:valid_types]).must_include :map
      _(d[:valid_types]).must_include :proc
    end

    it "should not report strict merge warning by default" do
      diags = lint('obj.merge(other)')
      ambiguous = diags.select { |d| d[:rule] == :ambiguous_method && d[:method] == 'merge' }
      _(ambiguous).must_be_empty
    end

    it "should report strict merge warning when strict is set" do
      diags = lint('obj.merge(other)', strict: true)
      d = diags.find { |d| d[:rule] == :ambiguous_method && d[:method] == 'merge' }
      _(d).wont_be_nil
      _(d[:valid_types]).must_include :set
    end
  end

  describe "automatic class reopening detection" do
    it "should treat class as extension when preceded by Struct.new" do
      js = to_js('Color = Struct.new(:name, :value); class Color; def to_s; value; end; end')
      # Should extend Color (no new class declaration)
      js.wont_include 'class Color'
      js.must_include 'Color.prototype'
    end

    it "should treat class as extension when preceded by Class.new with parent" do
      js = to_js('Animal = Class.new(Base); class Animal; def speak; "..."; end; end')
      js.wont_include 'class Animal'
      js.must_include 'Animal.prototype'
    end

    it "should not treat normal classes as extensions" do
      js = to_js('class MyClass; def foo; 1; end; end')
      # Regular class should create a class declaration
      js.must_include 'class MyClass'
    end

    it "should not confuse unrelated const assignments" do
      js = to_js('MAX = 100; class MAX; def val; MAX; end; end')
      # MAX = 100 is not Struct.new/Class.new, so class should be normal
      js.must_include 'class MAX'
    end
  end
end
