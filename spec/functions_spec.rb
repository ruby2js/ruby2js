require 'minitest/autorun'
require 'ruby2js/filter/functions'

describe Ruby2JS::Filter::Functions do

  def to_js(string)
    _(Ruby2JS.convert(string, filters: [Ruby2JS::Filter::Functions]).to_s)
  end

  def to_js_2015(string)
    _(Ruby2JS.convert(string, eslevel: 2015, filters: [Ruby2JS::Filter::Functions]).to_s)
  end

  def to_js_2020(string)
    _(Ruby2JS.convert(string, eslevel: 2020, filters: [Ruby2JS::Filter::Functions]).to_s)
  end

  def to_js_nullish(string)
    _(Ruby2JS.convert(string, eslevel: 2020, nullish_to_s: true, filters: [Ruby2JS::Filter::Functions]).to_s)
  end

  describe 'conversions' do
    it "should handle to_s" do
      to_js( 'a.to_s' ).must_equal 'a.toString()'
    end

    it "should handle to_s(16)" do
      to_js( 'a.to_s(16)' ).must_equal 'a.toString(16)'
    end

    it "should handle to_s with nullish_to_s option" do
      to_js_nullish( 'a.to_s' ).must_equal '(a ?? "").toString()'
    end

    it "should not wrap to_s(radix) with nullish_to_s option" do
      to_js_nullish( 'a.to_s(16)' ).must_equal 'a.toString(16)'
    end

    it "should handle String() with nullish_to_s option" do
      to_js_nullish( 'String(a)' ).must_equal 'String(a ?? "")'
    end

    it "should not transform String() without nullish_to_s option" do
      to_js_2020( 'String(a)' ).must_equal 'String(a)'
    end

    it "should handle to_i" do
      to_js( 'a.to_i' ).must_equal 'parseInt(a)'
    end

    it "should handle to_i(16)" do
      to_js( 'a.to_i' ).must_equal 'parseInt(a)'
    end

    it "should handle to_i with safe navigation" do
      to_js_2020( 'a&.to_i' ).must_equal 'parseInt(a)'
    end

    it "should handle to_f" do
      to_js( 'a.to_f' ).must_equal 'parseFloat(a)'
    end

    it "should handle to_f with safe navigation" do
      to_js_2020( 'a&.to_f' ).must_equal 'parseFloat(a)'
    end

    it "should handle puts" do
      to_js( 'puts "hi"' ).must_equal 'console.log("hi")'
    end

    it "should handle debugger statement" do
      to_js( 'debugger' ).must_equal 'debugger'
    end

    it "should handle typeof operator" do
      to_js( 'typeof(x)' ).must_equal 'typeof x'
    end

    it "should handle typeof in comparison" do
      to_js( 'typeof(x) == "function"' ).must_equal 'typeof x == "function"'
    end

    it "should handle to_json" do
      to_js( 'obj.to_json' ).must_equal 'JSON.stringify(obj)'
    end

    it "should handle to_json with replacer" do
      to_js( 'obj.to_json(replacer)' ).must_equal 'JSON.stringify(obj, replacer)'
    end

    it "should handle to_json with space argument" do
      to_js( 'obj.to_json(nil, "\t")' ).must_equal 'JSON.stringify(obj, null, "\t")'
    end

    it "should handle JSON.generate" do
      to_js( 'JSON.generate(obj)' ).must_equal 'JSON.stringify(obj)'
    end

    it "should handle JSON.dump" do
      to_js( 'JSON.dump(obj)' ).must_equal 'JSON.stringify(obj)'
    end

    it "should handle JSON.pretty_generate" do
      to_js( 'JSON.pretty_generate(obj)' ).must_equal 'JSON.stringify(obj, null, 2)'
    end

    it "should map JSON::ParserError to SyntaxError" do
      to_js( 'begin; rescue JSON::ParserError; end' ).must_equal 'try {} catch ($EXCEPTION) {if ($EXCEPTION instanceof SyntaxError) {} else {throw $EXCEPTION}}'
    end
  end

  describe :irange do
    it "(0..5).to_a" do
      to_js( '(0..5).to_a' ).must_equal('[...Array(6).keys()]')
    end

    it "(0..a).to_a" do
      to_js( '(0..a).to_a' ).must_equal('[...Array(a+1).keys()]')
    end

    it "(b..a).to_a" do
      to_js( '(b..a).to_a' ).must_equal('Array.from({length: (a-b+1)}, (_, idx) => idx+b)')
    end
  end

  describe :erange do
    it "(0...5).to_a" do
      to_js( '(0...5).to_a' ).must_equal('[...Array(5).keys()]')
    end

    it "(0...a).to_a" do
      to_js( '(0...a).to_a' ).must_equal('[...Array(a).keys()]')
    end

    it "(b...a).to_a" do
      to_js( '(b...a).to_a' ).must_equal('Array.from({length: (a-b)}, (_, idx) => idx+b)')
    end

    it "test range which contains reserved variable idx" do
      to_js( '(idx...i).to_a' ).must_equal('Array.from({length: (i-idx)}, (_, i$) => i$+idx)')
    end
  end

  describe 'string functions' do
    it 'should handle sub' do
      to_js( 'str.sub("a", "b")' ).must_equal 'str.replace("a", "b")'
      to_js( 'str.sub(/a/) {"x"}' ).
        must_equal 'str.replace(/a/, () => "x")'
      to_js( 'str.sub!("a", "b")' ).
        must_equal 'let str = str.replace("a", "b")'
      to_js( 'item.str.sub!("a", "b")' ).
        must_equal 'item.str = item.str.replace("a", "b")'
      to_js( '@str.sub!("a", "b")' ).
        must_equal 'this._str = this._str.replace("a", "b")'
      to_js( '@@str.sub!("a", "b")' ).
        must_equal 'this.constructor._str = this.constructor._str.replace("a", "b")'
      to_js( '$str.sub!("a", "b")' ).
        must_equal 'let $str = $str.replace("a", "b")'
      to_js( 'str.sub!(/a/) {"x"}' ).
        must_equal 'let str = str.replace(/a/, () => "x")'
      to_js( "str.sub(/a(.)/, 'b\\1')" ).
        must_equal 'str.replace(/a(.)/, "b$1")'
    end

    it 'should handle gsub and gsub!' do
      to_js( 'str.gsub("a", "b")' ).must_equal 'str.replace(/a/g, "b")'
      to_js( 'str.gsub(/a/i, "b")' ).must_equal 'str.replace(/a/gi, "b")'
      to_js( 'str.gsub(/a/, "b")' ).must_equal 'str.replace(/a/g, "b")'
      to_js( 'str.gsub(/#{a}/, "b")' ).
        must_equal 'str.replace(new RegExp(a, "g"), "b")'
      to_js( 'str.gsub(/a/) {"x"}' ).
        must_equal 'str.replace(/a/g, () => "x")'
      to_js( 'str.gsub!("a", "b")' ).
        must_equal 'let str = str.replace(/a/g, "b")'
      to_js( 'item.str.gsub!("a", "b")' ).
        must_equal 'item.str = item.str.replace(/a/g, "b")'
      to_js( 'str.gsub!(/a/, "b")' ).
        must_equal 'let str = str.replace(/a/g, "b")'
      to_js( "str.gsub(/a(.)/, 'b\\1')" ).
        must_equal 'str.replace(/a(.)/g, "b$1")'
    end

    it 'should handle scan' do
      to_js( 'str.scan(/\d/)' ).must_equal 'str.match(/\d/g)'
      to_js( 'str.scan(/(\d)(\d)/)' ).
        must_equal 'Array.from(str.matchAll(/(\d)(\d)/g), s => s.slice(1))'
      to_js( 'str.scan(pattern)' ).
        must_equal 'Array.from(str.matchAll(new RegExp(pattern, "g")), ' +
          's => s.slice(1))'
    end

    it 'should handle scan with block' do
      to_js( 'str.scan(/(\w+)/) { |m| puts m }' ).
        must_equal 'for (let $_ of str.matchAll(/(\w+)/g)) ' +
          '{let m = $_.slice(1); console.log(m)}'
      to_js( 'str.scan(/has_many\s+:(\w+)/) { |match| results << match[0] }' ).
        must_equal 'for (let $_ of str.matchAll(/has_many\s+:(\w+)/g)) ' +
          '{let match = $_.slice(1); results.push(match[0])}'
    end

    it 'should handle sort!' do
      to_js( 'str.sort! {|a, b| a - b}' ).
        must_equal 'str.sort((a, b) => a - b)'

      unless (RUBY_VERSION.split('.').map(&:to_i) <=> [2, 7, 0]) == -1
        to_js( 'str.sort! { _1 - _2}' ).
          must_equal 'str.sort((_1, _2) => _1 - _2)'
      end
    end

    it 'should handle ord and chr' do
      to_js( '"A".ord' ).must_equal '65'
      to_js( 'a.ord' ).must_equal 'a.charCodeAt(0)'
      to_js( '65.chr' ).must_equal '"A"'
      to_js( 'a.chr' ).must_equal 'String.fromCharCode(a)'
    end

    it 'should handle getbyte' do
      to_js( 'str.getbyte(0)' ).must_equal 'str.charCodeAt(0)'
      to_js( 'str.getbyte(n)' ).must_equal 'str.charCodeAt(n)'
    end

    it "should handle downcase" do
      to_js( 'x.downcase()' ).must_equal 'x.toLowerCase()'
    end

    it "should handle upcase" do
      to_js( 'x.upcase()' ).must_equal 'x.toUpperCase()'
    end

    it "should handle chained methods" do
      to_js( 'x.strip.downcase ').must_equal 'x.trim().toLowerCase()'
    end

    it 'should handle start_with?' do
      to_js( 'x.start_with?(y)' ).must_equal "x.startsWith(y)"
      to_js( 'x.start_with?("z")' ).must_equal "x.startsWith(\"z\")"
      # Multiple arguments: any prefix matches
      to_js( 'x.start_with?("a", "b")' ).must_equal '["a", "b"].some(_p => x.startsWith(_p))'
    end

    it 'should handle end_with?' do
      to_js( 'x.end_with?(y)' ).must_equal "x.endsWith(y)"
      to_js( 'x.end_with?("z")' ).must_equal "x.endsWith(\"z\")"
      # Multiple arguments: any suffix matches
      to_js( 'x.end_with?("a", "b")' ).must_equal '["a", "b"].some(_p => x.endsWith(_p))'
    end

    it 'should handle strip/lstrip/rstrip' do
      to_js( 'x.strip()' ).must_equal 'x.trim()'
      to_js( 'x.strip' ).must_equal 'x.trim()'
      to_js( 'a.lstrip()' ).must_equal "a.trimStart()"
      to_js( 'a.rstrip()' ).must_equal "a.trimEnd()"
    end

    it 'should handle chars' do
      to_js_2020( 'str.chars' ).must_equal 'Array.from(str)'
    end

    it 'should handle string multiply' do
      to_js( '" " * indent' ).must_equal "\" \".repeat(indent)"
      to_js_2020( '" " * indent' ).must_equal '" ".repeat(indent)'
    end

    it 'should handle ljust (padEnd)' do
      to_js( 'str.ljust(n)' ).must_equal 'str.padEnd(n)'
      to_js( 'str.ljust(10, "-")' ).must_equal 'str.padEnd(10, "-")'
    end

    it 'should handle rjust (padStart)' do
      to_js( 'str.rjust(n)' ).must_equal 'str.padStart(n)'
      to_js( 'str.rjust(10, "0")' ).must_equal 'str.padStart(10, "0")'
    end
  end

  describe 'array functions' do
    it "should map each to for statement" do
      to_js( 'a = 0; [1,2,3].each {|i| a += i}').
        must_equal 'let a = 0; for (let i of [1, 2, 3]) {a += i}'
    end

    it "should map each_with_index to forEach" do
      to_js( 'a = 0; [1,2,3].each_with_index {|n, i| a += n}').
        must_equal 'let a = 0; [1, 2, 3].forEach((n, i) => a += n)'
    end

    it "should handle first" do
      to_js( 'a.first' ).must_equal 'a[0]'
      to_js( 'a.first(n)' ).must_equal 'a.slice(0, n)'
    end

    it "should handle last" do
      to_js( 'a.last' ).must_equal 'a[a.length - 1]'
      to_js( 'a.last(n)' ).must_equal 'a.slice(a.length - n, a.length)'
    end

    it "should handle literal negative offsets" do
      to_js( 'a[-2]' ).must_equal 'a[a.length - 2]'
    end

    it "should handle inclusive ranges" do
      to_js( 'a[2..4]' ).must_equal 'a.slice(2, 5)'
      to_js( 'a[2..-1]' ).must_equal 'a.slice(2)'
      to_js( 'a[-2..-1]' ).must_equal 'a.slice(-2)'
      to_js( 'a[-4..-2]' ).must_equal 'a.slice(-4, -1)'
      to_js( 'a[-4..-3]' ).must_equal 'a.slice(-4, -2)'
      to_js( 'a[i..j]' ).must_equal 'a.slice(i, j + 1)'

      unless (RUBY_VERSION.split('.').map(&:to_i) <=> [2, 6, 0]) == -1
        to_js( 'a[i..]' ).must_equal 'a.slice(i)'
      end
    end

    it "should handle exclusive ranges" do
      to_js( 'a[2...4]' ).must_equal 'a.slice(2, 4)'
      to_js( 'a[-4...-2]' ).must_equal 'a.slice(a.length - 4, -2)'
      to_js( 'a[i...j]' ).must_equal 'a.slice(i, j)'

      unless (RUBY_VERSION.split('.').map(&:to_i) <=> [2, 6, 0]) == -1
        to_js( 'a[i...]' ).must_equal 'a.slice(i)'
      end
    end

    it "should handle join" do
      to_js( 'a.join' ).must_equal 'a.join("")'
      to_js( 'a.join(",")' ).must_equal 'a.join(",")'
    end

    it "should handle slice! with ranges" do
      to_js( 'a.slice!(1..-1)' ).must_equal 'a.splice(1)'
      to_js( 'a.slice!(1..3)' ).must_equal 'a.splice(1, 3 - 1 + 1)'
      to_js( 'a.slice!(1...3)' ).must_equal 'a.splice(1, 3 - 1)'
      to_js( 'a.slice!(2)' ).must_equal 'a.splice(2, 1)'
    end

    it "should handle slice! with variable range endpoints" do
      to_js( 'a.slice!(x..-1)' ).must_equal 'a.splice(x)'
      to_js( 'a.slice!(x..y)' ).must_equal 'a.splice(x, y - x + 1)'
      to_js( 'a.slice!(x...y)' ).must_equal 'a.splice(x, y - x)'
      to_js( 'a.slice!(mark.first + 1..-1)' ).must_equal 'a.splice(mark[0] + 1)'
    end

    it "should handle array multiplication" do
      # Single element array: use Array(n).fill(element)
      to_js( '["x"] * 5' ).must_equal 'Array(5).fill("x")'
      to_js( '[1] * n' ).must_equal 'Array(n).fill(1)'
      # Multi-element array: use Array.from with flatMap
      to_js( '[1, 2] * 3' ).must_equal 'Array.from({length: 3}, () => ([1, 2])).flat()'
      to_js( '["a", "b"] * n' ).must_equal 'Array.from({length: n}, () => (["a", "b"])).flat()'
    end

    it "should handle array concatenation with +" do
      to_js( '[1, 2] + [3]' ).must_equal '[1, 2].concat([3])'
      to_js( 'a + [1, 2]' ).must_equal 'a.concat([1, 2])'
      to_js( '["x"] * 3 + ["y"]' ).must_equal 'Array(3).fill("x").concat(["y"])'
    end

    it "should handle compact on arrays" do
      to_js( 'a.compact' ).must_equal 'a.filter(x => x != null)'
    end

    it "should handle compact! on arrays (mutating)" do
      to_js( 'a.compact!' ).must_equal 'a.splice(0, a.length, ...a.filter(x => x != null))'
    end

    it "should not convert compact with block to filter" do
      # compact with a block is NOT the array compact method
      # e.g., serializer.compact { } should remain as compact, not become filter
      to_js( 'obj.compact { puts "x" }' ).must_equal 'obj.compact(() => console.log("x"))'
    end

    it "should handle range assignment" do
      to_js_2015( 'a[0..2] = v' ).must_equal 'a.splice(0, 2 - 0 + 1, ...v)'
      to_js_2015( 'a[0...2] = v' ).must_equal 'a.splice(0, 2 - 0, ...v)'
      to_js_2015( 'a[1..-1] = v' ).must_equal 'a.splice(1, a.length - 1, ...v)'
    end

    it "should handle regular expression indexes" do
      to_js( 'a[/\d+/]' ).must_equal 'a.match(/\\d+/)?.[0]'
      to_js( 'a[/(\d+)/, 1]' ).must_equal 'a.match(/(\\d+)/)?.[1]'
    end

    it "should handle regular expression index assignment" do
      to_js( 'a[/a(b)/, 1] = "d"' ).must_equal(
        'let a = a.replace(/(a)(b)/, "$1d")')
      to_js( 'a[/a(b)c/, 1] = "d"' ).must_equal(
        'let a = a.replace(/(a)(b)(c)/, "$1d$3")')
      to_js( 'a[/a()c/, 1] = "d"' ).must_equal(
        'let a = a.replace(/(a)(c)/, "$1d$2")')
      to_js( 'a[/(b)c/, 1] = "#{d}"' ).must_equal(
        'let a = a.replace(/(b)(c)/, ' +
        'match => `${d}${match[1]}`)')
      to_js( 'a[/^a(b)c/, 1] = d' ).must_equal(
        'let a = a.replace(/^(a)(b)(c)/m, ' +
        'match => `${match[0]}${d}${match[2]}`)')
    end

    it "should handle empty?" do
      to_js( 'a.empty?' ).must_equal 'a.length == 0'
    end

    it "should handle empty? with safe navigation" do
      to_js_2020( 'a&.empty?' ).must_equal 'a?.length == 0'
    end

    it "should handle double negation of empty?" do
      to_js( '!!a.empty?' ).must_equal 'a.length == 0'
      to_js( '!!!a.empty?' ).must_equal 'a.length != 0'
    end

    it "should handle nil?" do
      to_js( 'a.nil?' ).must_equal 'a == null'
    end

    it "should handle nil? on index result with === -1" do
      # Ruby's String#index returns nil when not found, but JS indexOf returns -1
      # When a variable is assigned from .index(), .nil? should use === -1
      to_js( 'idx = str.index("x"); idx.nil?' ).must_equal 'let idx = str.indexOf("x"); idx === -1'
    end

    it "should reset index tracking per method" do
      # Variables assigned from .index() in one method should not affect
      # .nil? checks in other methods
      to_js( 'def foo; idx = s.index("x"); idx.nil?; end; def bar; idx = 1; idx.nil?; end' ).
        must_equal 'function foo() {let idx = s.indexOf("x"); idx === -1}; function bar() {let idx = 1; idx == null}'
    end

    it "should handle zero?" do
      to_js( 'n.zero?' ).must_equal 'n === 0'
    end

    it "should handle positive?" do
      to_js( 'n.positive?' ).must_equal 'n > 0'
    end

    it "should handle negative?" do
      to_js( 'n.negative?' ).must_equal 'n < 0'
    end

    it "should handle positive? with safe navigation" do
      to_js_2020( 'n&.positive?' ).must_equal 'n > 0'
    end

    it "should handle negative? with safe navigation" do
      to_js_2020( 'n&.negative?' ).must_equal 'n < 0'
    end

    it "should handle clear" do
      to_js( 'a.clear()' ).must_equal 'a.length = 0'
    end

    it "should handle replace" do
      to_js( 'a.replace(b)' ).
        must_equal 'a.length = 0; a.push(...b)'
    end

    it "should handle simple include?" do
      to_js( 'a.include? b' ).must_equal "a.includes(b)"
    end

    it "should handle erange include?" do
      to_js( '(0...1).include? a' ).must_equal 'a >= 0 && a < 1'
    end

    it "should handle irange include?" do
      to_js( '(0..5).include? a' ).must_equal 'a >= 0 && a <= 5'
    end

    it "should handle respond_to?" do
      to_js( 'a.respond_to? b' ).must_equal 'b in a'
      to_js( '!a.respond_to? b' ).must_equal '!(b in a)'
      # respond_to? && property should not be rewritten to optional chaining
      to_js_2020( 'a.respond_to?(:foo) && a.foo' ).
        must_equal '"foo" in a && a.foo'
    end

    it "should handle respond_to? with safe navigation" do
      # &.respond_to? should include null check
      to_js_2020( 'a&.respond_to?(:foo)' ).must_equal 'a != null && "foo" in a'
    end

    it "should handle has_key?/key?/member?" do
      to_js( 'h.has_key?(:foo)' ).must_equal '"foo" in h'
      to_js( 'h.key?(:foo)' ).must_equal '"foo" in h'
      to_js( 'h.member?(:foo)' ).must_equal '"foo" in h'
    end

    it "should handle any? with block" do
      to_js( 'a.any? {|i| i==0}' ).
        must_equal 'a.some(i => i == 0)'
    end

    it "should handle any? without block" do
      to_js( 'a.any?' ).must_equal 'a.some(Boolean)'
    end

    it "should handle all? without block" do
      to_js( 'a.all?' ).must_equal 'a.every(Boolean)'
    end

    it "should handle none? with block" do
      to_js( 'a.none? {|i| i==0}' ).
        must_equal '!a.some(i => i == 0)'
    end

    it "should handle none? without block" do
      to_js( 'a.none?' ).must_equal '!a.some(Boolean)'
    end

    it "should handle map" do
      to_js( 'a.map {|i| i+1}' ).
        must_equal 'a.map(i => i + 1)'
    end

    it "should handle flat_map" do
      to_js( 'a.flat_map {|i| [i, i*2]}' ).
        must_equal 'a.flatMap(i => ([i, i * 2]))'
    end

    it "should handle range.map starting from 0" do
      to_js_2020( '(0..5).map {|i| i*2}' ).
        must_equal 'Array.from({length: 5 + 1}, (_, i) => i * 2)'
      to_js_2020( '(0...n).map {|i| i*2}' ).
        must_equal 'Array.from({length: n}, (_, i) => i * 2)'
    end

    it "should handle range.map starting from 1" do
      to_js_2020( '(1..5).map {|i| i*2}' ).
        must_equal 'Array.from({length: 5}, (_, $i) => {let i = $i + 1; return i * 2})'
      to_js_2020( '(1..n).map {|i| i*2}' ).
        must_equal 'Array.from({length: n}, (_, $i) => {let i = $i + 1; return i * 2})'
    end

    it "should handle range.map with general start" do
      to_js_2020( '(a..b).map {|i| i*2}' ).
        must_equal 'Array.from({length: b - a + 1}, (_, $i) => {let i = $i + a; return i * 2})'
    end

    it "should handle find" do
      to_js( 'a.find {|i| i<0}' ).
        must_equal 'a.find(i => i < 0)'
    end

    it "should handle find_index" do
      to_js( 'a.find_index {|i| i<0}' ).
        must_equal 'a.findIndex(i => i < 0)'
    end

    it "should handle index with block" do
      to_js( 'a.index {|i| i<0}' ).
        must_equal 'a.findIndex(i => i < 0)'
    end

    it "should handle index with arg" do
      to_js( 'a.index("abc")' ).
        must_equal 'a.indexOf("abc")'
    end

    it "should NOT handle index as a property" do
      to_js( 'a.index' ).
        must_equal 'a.index'
    end

    it "should handle rindex" do
      to_js( 'a.rindex("abc")' ).
        must_equal 'a.lastIndexOf("abc")'
    end

    it "should handle all?" do
      to_js( 'a.all? {|i| i==0}' ).
        must_equal 'a.every(i => i == 0)'
    end

    it "should handle max" do
      to_js( 'a.max' ).must_equal 'a.max'
      to_js( 'a.max()' ).must_equal "Math.max(...a)"
      to_js( '[a,b].max' ).must_equal 'Math.max(a, b)'
    end

    it "should handle min" do
      to_js( 'a.min' ).must_equal 'a.min'
      to_js( 'a.min()' ).must_equal "Math.min(...a)"
      to_js( '[a,b].min' ).must_equal 'Math.min(a, b)'
    end

    it "should handle min" do
      to_js( 'rand' ).must_equal 'Math.random()'
      to_js( 'rand(50)' ).must_equal 'parseInt(Math.random() * 50)'
      to_js( 'rand(0..n)' ).must_equal 'parseInt(Math.random() * (n + 1))'
      to_js( 'rand(1..n)' ).must_equal 'parseInt(Math.random() * n + 1)'
      to_js( 'rand(n...m)' ).must_equal 'parseInt(Math.random() * (m - n) + n)'
    end

    it "should handle sum" do
      to_js( 'a.sum' ).must_equal "a.reduce((a, b) => a + b, 0)"
    end

    it "should handle reduce with symbol" do
      to_js( 'a.reduce(:+)' ).must_equal "a.reduce((a, b) => a + b)"
      to_js( 'a.reduce(:*)' ).must_equal "a.reduce((a, b) => a * b)"
      to_js( 'a.reduce(:merge)' ).must_equal "a.reduce((a, b) => ({...a, ...b}))"
      to_js( 'a.inject(:+)' ).must_equal "a.reduce((a, b) => a + b)"
    end

    it "should handle group_by with destructuring" do
      to_js( 'a.group_by {|k, v| k.to_s}' ).
        must_equal 'a.reduce(($acc, [k, v]) => {let $key = k.toString(); ($acc[$key] = $acc[$key] ?? []).push([k, v]); return $acc}, {})'
    end

    it "should handle map with destructuring" do
      to_js( 'a.map {|k, v| k + v}' ).
        must_equal 'a.map(([k, v]) => k + v)'
    end

    unless (RUBY_VERSION.split('.').map(&:to_i) <=> [3, 4, 0]) == -1
      it "should handle map with Ruby 3.4 it implicit parameter" do
        to_js( 'a.map { it * 2 }' ).
          must_equal 'a.map(it => it * 2)'
      end

      it "should handle sort_by with Ruby 3.4 it implicit parameter" do
        to_js( 'items.sort_by { it.slot || 0 }' ).
          must_equal 'items.sort_by(it => it.slot ?? 0)'
      end
    end

    it "should map .select to .filter" do
      to_js( 'a.select {|item| item > 0}' ).
        must_equal 'a.filter(item => item > 0)'
    end

    it "should map .find_all to .filter" do
      to_js( 'a.find_all {|item| item > 0}' ).
        must_equal 'a.filter(item => item > 0)'
    end

    it "should map .select! to .splice(0, .length, .filter)" do
      to_js( 'a.select! {|item| item > 0}' ).
        must_equal 'a.splice(...[0, a.length].concat(a.filter(item => item > 0)))'
    end

    it "should map .map! to .splice(0, .length, .map)" do
      to_js( 'a.map! {|item| -item}' ).
        must_equal 'a.splice(...[0, a.length].concat(a.map(item => -item)))'
    end

    it "should map .reverse! to .splice(0, .length, .reverse)" do
      to_js( 'a.reverse!()' ).
        must_equal 'a.splice(0, a.length, ...a.reverse())'
    end

    it "should ensure .reverse has parentheses" do
      to_js( 'a.reverse.each { |x| }' ).
        must_include 'a.reverse()'
    end

    it "should map Array(foo) to Array.from(foo)" do
      to_js( 'Array(foo)' ).
        must_equal 'Array.from(foo)'
    end

    it "should map Array.new with two args to fill" do
      to_js_2020( 'Array.new(5, 1)').
        must_equal 'new Array(5).fill(1)'
    end

    it "should handle flatten" do
      to_js( 'a.flatten()' ).must_equal 'a.flat(Infinity)'
      to_js( 'a.flatten' ).must_equal 'a.flat(Infinity)'
    end

    it "should handle to_h" do
      to_js( 'a.to_h' ).must_equal 'Object.fromEntries(a)'
    end

    it "should handle Hash[]" do
      to_js( 'Hash[a]' ).must_equal 'Object.fromEntries(a)'
    end
  end

  describe 'hash functions' do
    it "should map each_pair to Object.entries().forEach" do
      to_js( 'h.each_pair {|key, i| a += i}').
        must_equal 'for (let [key, i] of Object.entries(h)) {a += i}'
    end

    it "should map each_value to forEach" do
      to_js( 'h.each_value {|i| a += i}').
        must_equal 'for (let i of h) {a += i}'
    end

    it "should handle keys" do
      to_js( 'a.keys' ).must_equal 'a.keys'
      to_js( 'a.keys()' ).must_equal 'Object.keys(a)'
    end

    it "should handle values" do
      to_js( 'a.values' ).must_equal 'a.values'
      to_js( 'a.values()' ).must_equal 'Object.values(a)'
    end

    it "should handle entries" do
      to_js( 'a.entries' ).must_equal 'a.entries'
      to_js( 'a.entries()' ).must_equal 'Object.entries(a)'
    end

    it "should convert hash.each_key" do
      to_js( 'h.each_key {|k| x+=k}' ).
        must_equal 'for (let k in h) {x += k}'
    end

    it "should handle merge" do
      to_js( 'b={}; a = a.merge(b)' ).
        must_equal  "let b = {}; let a = {...a, ...b}"
    end

    it "should handle merge with a constant hash" do
      # simple LHS
      to_js( 'a = a.merge(b: 1)' ).
        must_equal  "let a = {...a, b: 1}"

      # computed LHS
      to_js( 'a.b.merge(b: 1)' ).
        must_equal  "{...a.b, b: 1}"
    end

    it "should handle merge!" do
      to_js( 'b={}; a.merge!(b)' ).
        must_equal "let b = {}; Object.assign(a, b)"
    end

    it "should handle merge! with a constant hash" do
      to_js( 'a.merge!(b: 1)' ).
        must_equal "a.b = 1"
    end

    it "should handle delete attribute (ruby style) - static" do
      to_js( 'a.delete "x"' ).must_equal 'delete a.x'
    end

    it "should handle delete attribute (ruby style) - dynamic" do
      to_js( 'a.delete x' ).must_equal 'delete a[x]'
    end

    it "should handle delete attribute (js style)" do
      to_js( 'delete a.x' ).must_equal 'delete a.x'
    end

    it "should handle delete with key containing space" do
      to_js( 'a.delete "NOT NULL"' ).must_equal 'delete a["NOT NULL"]'
    end

    it "should handle delete with key containing hyphen" do
      to_js( 'a.delete "content-type"' ).must_equal 'delete a["content-type"]'
    end

    it "should handle delete with key starting with number" do
      to_js( 'a.delete "123key"' ).must_equal 'delete a["123key"]'
    end

    it "should not map delete blocks" do
      to_js( 'HTTP.delete("x") {}' ).
        must_equal 'HTTP.delete("x", () => {})'
    end

    it "should not map delete chains" do
      to_js( 'HTTP.delete("x").then {}' ).
        must_equal 'HTTP.delete("x").then(() => {})'
    end
  end

  describe 'instance tests' do
    it "should map is_a? Boolean" do
      to_js( 'true.is_a? Boolean' ).
        must_equal 'typeof true === "boolean"'
    end

    it "should map kind_of? Regexp" do
      to_js( '/a/.kind_of? RegExp' ).
        must_equal '/a/ instanceof RegExp'
    end

    it "should map kind_of? Array" do
      to_js( '[3].kind_of? Array' ).
        must_equal 'Array.isArray([3])'
    end

    it "should map kind_of? Float" do
      to_js( '3.2.kind_of? Float' ).
        must_equal 'typeof 3.2 === "number"'
    end

    it "should map is_a? Integer" do
      to_js( '3.is_a? Integer' ).
        must_equal 'typeof 3 === "number" && Number.isInteger(3)'
    end

    it "should map is_a? String" do
      to_js( '"x".is_a? String' ).
        must_equal 'typeof "x" === "string"'
    end

    it "should map is_a? Hash" do
      to_js( '{}.is_a? Hash' ).
        must_equal 'typeof {} === "object" && {} !== null && !Array.isArray({})'
    end

    it "should map is_a? to instanceof for user classes" do
      to_js( 'x.is_a? MyClass' ).
        must_equal 'x instanceof MyClass'
    end

    it "should map instance_of? to constructor check" do
      to_js( 'x.instance_of? MyClass' ).
        must_equal 'x.constructor === MyClass'
    end

    it "should map instance_of? Array" do
      to_js( 'x.instance_of? Array' ).
        must_equal 'x.constructor === Array'
    end

    it "should map instance_of? Hash to Object constructor" do
      to_js( 'x.instance_of? Hash' ).
        must_equal 'x.constructor === Object'
    end

    it "should map respond_to? to in check" do
      to_js( 'x.respond_to? :foo' ).
        must_equal '"foo" in x'
    end

    it "should map .class to constructor" do
      to_js( 'x.class' ).
        must_equal 'x.constructor'
    end

    it "should map .class.name to constructor.name" do
      to_js( 'x.class.name' ).
        must_equal 'x.constructor.name'
    end

    it "should map superclass to prototype chain" do
      to_js( 'Foo.superclass' ).
        must_equal 'Object.getPrototypeOf(Foo.prototype).constructor'
    end
  end

  describe 'step' do
    it "should map upto to for" do
      to_js( '1.upto(3) {|i| p i}' ).
        must_equal 'for (let i = 1; i <= 3; i++) {p(i)}'
    end

    it "should map downto to for" do
      to_js( '3.downto(1) {|i| p i}' ).
        must_equal 'for (let i = 3; i >= 1; i--) {p(i)}'
    end

    it "should range each to for" do
      to_js( '(1..10).each {|i| p i}' ).
        must_equal 'for (let i = 1; i <= 10; i++) {p(i)}'
      to_js( '(1...10).each {|i| p i}' ).
        must_equal 'for (let i = 1; i < 10; i++) {p(i)}'
    end

    it "should handle each with no block arguments" do
      to_js( '(1...5).each do; puts "hi"; end' ).
        must_equal 'for (let _ = 1; _ < 5; _++) {console.log("hi")}'
      to_js( '[1,2,3].each do; puts "hi"; end' ).
        must_equal 'for (let _ of [1, 2, 3]) {console.log("hi")}'
    end

    it "should map step().each to for -- default" do
      to_js( '1.step(3).each {|i| p i}' ).
        must_equal 'for (let i = 1; i <= 3; i++) {p(i)}'
    end

    it "should map step().each to for -- forward" do
      to_js( '1.step(3, 2).each {|i| p i}' ).
        must_equal 'for (let i = 1; i <= 3; i += 2) {p(i)}'
    end

    it "should map step().each to for -- reverse" do
      to_js( '5.step(1, -2).each {|i| p i}' ).
        must_equal 'for (let i = 5; i >= 1; i -= 2) {p(i)}'
    end
  end

  describe 'setTimeout/setInterval' do
    it "should handle setTimeout with first parameter passed as a block" do
      to_js( 'setInterval(100) {x()}' ).
        must_equal 'setInterval(() => x(), 100)'
    end

    it "should handle snake case" do
      to_js( 'set_interval 100 do; x(); end' ).
        must_equal 'set_interval(() => x(), 100)' # to be processed by camelCase
    end

    it "should handle setInterval with first parameter passed as a block" do
      to_js( 'setInterval(100) {x()}' ).
        must_equal 'setInterval(() => x(), 100)'
    end
  end

  describe 'block-pass' do
    it 'should handle properties' do
      to_js( 'a.all?(&:ready)' ).
        must_equal 'a.every(item => item.ready)'
    end

    it 'should handle well known methods' do
      to_js( 'a.map(&:to_i)' ).
        must_equal 'a.map(item => parseInt(item))'
    end

    it 'should handle binary operators' do
      to_js( 'a.sort(&:<)' ).
        must_equal 'a.sort((a, b) => a < b)'
    end

    it 'should handle block arguments' do
      to_js( 'a.sort(&b)' ).
        must_equal 'a.sort(b)'
    end

    it 'should handles loops' do
      to_js( 'loop {sleep 1; break}' ).
        must_equal 'while (true) {sleep(1); break}'
    end

    it 'should handle times with block variable' do
      to_js( '3.times { |i| console.log(i) }' ).
        must_equal 'for (let i = 0; i < 3; i++) {console.log(i)}'
    end

    it 'should handle times without block variable' do
      to_js( '3.times { console.log("hi") }' ).
        must_equal 'for (let _ = 0; _ < 3; _++) {console.log("hi")}'
    end

    it 'should handle times with variable count' do
      to_js( 'n.times { |i| console.log(i) }' ).
        must_equal 'for (let i = 0; i < n; i++) {console.log(i)}'
    end

    it 'should handles inspect' do
      to_js( 'a.inspect' ).must_equal 'JSON.stringify(a)'
    end
  end

  describe 'call functions' do
    it 'should handles lvars' do
      to_js( '@f.call(1, 2, 3)' ).must_equal 'this._f(1, 2, 3)'
    end

    it 'should handles cvars' do
      to_js( '@@f.call(1, 2, 3)' ).must_equal 'this.constructor._f(1, 2, 3)'
    end

    it 'should handle safe navigation with ivar call' do
      to_js_2020( '@f&.call(1, 2, 3)' ).must_equal 'this._f?.(1, 2, 3)'
    end

    it 'should handle safe navigation with cvar call' do
      to_js_2020( '@@f&.call(1, 2, 3)' ).must_equal 'this.constructor._f?.(1, 2, 3)'
    end

    it 'should handle safe navigation call with include option' do
      _(Ruby2JS.convert('foo&.call(x)', eslevel: 2020, include: [:call],
        filters: [Ruby2JS::Filter::Functions]).to_s).must_equal 'foo?.(x)'
    end
  end

  describe 'Exceptions' do
    it 'should throw new Error' do
      to_js( 'raise Exception.new("foo")' ).
        must_equal 'throw new Error("foo")'
    end

    it 'should create an Exception contructor' do
      to_js( 'class E < Exception; end' ).
        must_equal 'class E extends Error {constructor(message) {' +
          'this.message = message; this.name = "E"; this.stack = Error(message).stack}}'
    end
  end

  describe "tap and yield_self" do
    it 'should handle tap' do
      to_js( 'foo.tap {|bar| puts bar}' ).
        must_equal '((bar) => {console.log(bar); return bar})(foo)'
    end

    it 'should handle yield_self' do
      to_js( 'foo.yield_self {|n| n*n}' ).
        must_equal '(n => n * n)(foo)'
    end
  end

  describe "sort_by, max_by, min_by" do
    it "should handle sort_by" do
      to_js( 'a.sort_by { |x| x.name }' ).
        must_equal 'a.slice().sort((x_a, x_b) => {if (x_a.name < x_b.name) {return -1} else if (x_a.name > x_b.name) {return 1} else {return 0}})'
    end

    it "should handle sort_by with method call" do
      to_js( 'words.sort_by { |w| w.length }' ).
        must_equal 'words.slice().sort((w_a, w_b) => {if (w_a.length < w_b.length) {return -1} else if (w_a.length > w_b.length) {return 1} else {return 0}})'
    end

    it "should handle sort_by with arithmetic expression" do
      to_js( 'items.sort_by { |i| i.price * i.quantity }' ).
        must_equal 'items.slice().sort((i_a, i_b) => {if (i_a.price * i_a.quantity < i_b.price * i_b.quantity) {return -1} else if (i_a.price * i_a.quantity > i_b.price * i_b.quantity) {return 1} else {return 0}})'
    end

    it "should handle max_by" do
      to_js( 'a.max_by { |x| x.score }' ).
        must_equal 'a.reduce((a, b) => a.score >= b.score ? a : b)'
    end

    it "should handle max_by with method call" do
      to_js( 'words.max_by { |w| w.length }' ).
        must_equal 'words.reduce((a, b) => a.length >= b.length ? a : b)'
    end

    it "should handle max_by with arithmetic expression" do
      to_js( 'items.max_by { |i| i.price * i.qty }' ).
        must_equal 'items.reduce((a, b) => a.price * a.qty >= b.price * b.qty ? a : b)'
    end

    it "should handle min_by" do
      to_js( 'a.min_by { |x| x.score }' ).
        must_equal 'a.reduce((a, b) => a.score <= b.score ? a : b)'
    end

    it "should handle min_by with method call" do
      to_js( 'words.min_by { |w| w.length }' ).
        must_equal 'words.reduce((a, b) => a.length <= b.length ? a : b)'
    end

    it "should handle min_by with arithmetic expression" do
      to_js( 'items.min_by { |i| i.price * i.qty }' ).
        must_equal 'items.reduce((a, b) => a.price * a.qty <= b.price * b.qty ? a : b)'
    end

    it "should handle sort_by with nested destructuring" do
      to_js( 'scores.sort_by { |(pid, cid), _| cid }' ).
        must_include '[[pid_a, cid_a], __a]'
    end
  end

  describe "each with nested destructuring" do
    it "should handle nested mlhs in each block" do
      to_js( 'hash.each { |(a, b), c| puts a }' ).
        must_include 'let [[a, b], c]'
    end

    it "should handle splat in nested mlhs" do
      to_js( 'scores.each { |(score, *students), count| puts score }' ).
        must_include 'let [[score, ...students], count]'
    end
  end

  describe "group_by" do
    it "should handle group_by with simple key" do
      to_js_2020( 'users.group_by { |u| u.role }' ).
        must_equal 'users.reduce(($acc, u) => {let $key = u.role; ($acc[$key] = $acc[$key] ?? []).push(u); return $acc}, {})'
    end

    it "should handle group_by with method call" do
      to_js_2020( 'words.group_by { |w| w.length }' ).
        must_equal 'words.reduce(($acc, w) => {let $key = w.length; ($acc[$key] = $acc[$key] ?? []).push(w); return $acc}, {})'
    end

    it "should handle group_by with ternary expression" do
      to_js_2020( 'nums.group_by { |n| n > 0 ? "positive" : "non_positive" }' ).
        must_equal 'nums.reduce(($acc, n) => {let $key = n > 0 ? "positive" : "non_positive"; ($acc[$key] = $acc[$key] ?? []).push(n); return $acc}, {})'
    end

    it "should handle group_by with arithmetic expression" do
      to_js_2020( 'items.group_by { |i| i.price / 10 }' ).
        must_equal 'items.reduce(($acc, i) => {let $key = i.price / 10; ($acc[$key] = $acc[$key] ?? []).push(i); return $acc}, {})'
    end
  end

  describe "math functions" do
    it "should handle abs" do
      to_js( 'a.abs' ).must_equal 'Math.abs(a)'
    end

    it "should handle round" do
      to_js( 'a.round' ).must_equal 'Math.round(a)'
    end

    it "should handle ceil" do
      to_js( 'a.ceil' ).must_equal 'Math.ceil(a)'
    end

    it "should handle floor" do
      to_js( 'a.floor' ).must_equal 'Math.floor(a)'
    end
  end

  describe "introspection and metaprogramming" do
    it "should handle method_defined?" do
      to_js( 'a.method_defined? :meth').must_equal '"meth" in a.prototype'
      to_js( 'a.method_defined? :meth, true').must_equal '"meth" in a.prototype'
      to_js( 'a.method_defined? :meth, false').must_equal 'a.prototype.hasOwnProperty("meth")'
      to_js( 'result = a.method_defined? :meth, expr').
        must_equal 'let result = expr ? "meth" in a.prototype : a.prototype.hasOwnProperty("meth")'
    end

    it "should handle alias_method" do
      to_js( 'Klass.alias_method :newname, :oldname').must_equal 'Klass.prototype.newname = Klass.prototype.oldname'
      to_js_2020( 'class C; alias_method :c, :d; end').
        must_equal 'class C {}; C.prototype.c = C.prototype.d'
    end

    it "should handle define_method" do
      to_js_2020( 'Klass.define_method(:newname) {|x| return x * 5 }').must_equal 'Klass.prototype.newname = function(x) {return x * 5}'
      to_js_2020( 'Klass.define_method(newname) {|x| return x * 5 }').must_equal 'Klass.prototype[newname] = function(x) {return x * 5}'
      # define_method without receiver inside class body
      to_js_2020( 'class Klass; define_method(:foo) {|x| x + 1}; end').
        must_equal 'class Klass {}; Klass.prototype.foo = function(x) {x + 1}'
      # define_method with block variable (inside method body)
      to_js_2020( 'define_method(:foo, myblock)').
        must_equal 'this.constructor.prototype.foo = myblock'
      to_js_2020( 'define_method(name, myblock)').
        must_equal 'this.constructor.prototype[name] = myblock'
    end

    it "should handle define_method inside loops" do
      to_js_2020( 'class Klass; [:a, :b].each { |m| define_method(m) { } }; end').
        must_equal 'class Klass {}; for (let m of ["a", "b"]) {Klass.prototype[m] = function() {}}'
    end

    it "should handle method_defined? in class body" do
      to_js_2020( 'class Klass; method_defined?(:foo); end').
        must_equal 'class Klass {}; "foo" in Klass.prototype'
    end

    it "should handle method_defined? inside loops" do
      to_js_2020( 'class Klass; [:a, :b].each { |m| define_method(m) { } unless method_defined?(m) }; end').
        must_include 'Klass.prototype'
    end

    it "should handle method(:name)" do
      to_js( 'method(:foo)' ).must_equal 'this.foo.bind(this)'
      to_js( 'method(name)' ).must_equal 'this[name].bind(this)'
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include Functions" do
      _(Ruby2JS::Filter::DEFAULTS).must_include Ruby2JS::Filter::Functions
    end
  end

  describe "explicit inclusion of methods" do
    def to_js_include(string, methods)
      _(Ruby2JS.convert(string, eslevel: 2017, include: methods, filters: [Ruby2JS::Filter::Functions]).to_s)
    end

    def to_js_include_all(string)
      _(Ruby2JS.convert(string, eslevel: 2017, include_all: true, filters: [Ruby2JS::Filter::Functions]).to_s)
    end

    it "should convert keys without parens when explicitly included" do
      to_js_include( 'a.keys', [:keys] ).must_equal 'Object.keys(a)'
    end

    it "should convert max without parens when explicitly included" do
      to_js_include( 'a.max', [:max] ).must_equal 'Math.max(...a)'
    end

    it "should convert index without parens when explicitly included" do
      to_js_include( 'a.index', [:index] ).must_equal 'a.indexOf'
    end

    it "should convert values without parens when include_all is true" do
      to_js_include_all( 'a.values' ).must_equal 'Object.values(a)'
    end

    it "should convert clear without parens when include_all is true" do
      to_js_include_all( 'a.clear' ).must_equal 'a.length = 0'
    end
  end

  describe "freeze" do
    it "should handle .freeze" do
      to_js( 'obj.freeze' ).must_equal 'Object.freeze(obj)'
    end

    it "should handle .freeze on literal" do
      to_js( '{a: 1}.freeze' ).must_equal 'Object.freeze({a: 1})'
    end

    it "should handle .freeze on array" do
      to_js( '[1, 2, 3].freeze' ).must_equal 'Object.freeze([1, 2, 3])'
    end
  end

  describe "negative index assignment" do
    it "should handle arr[-1] = x" do
      to_js( 'arr[-1] = x' ).must_equal 'arr[arr.length - 1] = x'
    end

    it "should handle arr[-2] = x" do
      to_js( 'arr[-2] = x' ).must_equal 'arr[arr.length - 2] = x'
    end

    it "should handle ivar target with negative index" do
      to_js( '@arr[-1] = x' ).must_equal 'this._arr[this._arr.length - 1] = x'
    end
  end

  describe "two-argument slice" do
    it "should handle str[0, 5]" do
      to_js( 'str[0, 5]' ).must_equal 'str.slice(0, 0 + 5)'
    end

    it "should handle str[3, 2]" do
      to_js( 'str[3, 2]' ).must_equal 'str.slice(3, 3 + 2)'
    end

    it "should handle negative start" do
      to_js( 'str[-3, 2]' ).must_equal 'str.slice(str.length - 3, str.length - 3 + 2)'
    end

    it "should handle non-integer arguments" do
      to_js( 'str[start, length]' ).must_equal 'str.slice(start, start + length)'
    end

    it "should handle method call arguments" do
      to_js( 'str[node.offset, node.length]' ).must_equal 'str.slice(node.offset, node.offset + node.length)'
    end
  end

  describe "reject with block" do
    it "should handle reject with block" do
      to_js( 'arr.reject { |x| x.empty? }' ).must_equal 'arr.filter(x => !(x.length == 0))'
    end

    it "should handle reject with simple condition" do
      to_js( 'arr.reject { |n| n > 5 }' ).must_equal 'arr.filter(n => !(n > 5))'
    end

    it "should handle reject(&:method) symbol-to-proc" do
      to_js( 'arr.reject(&:empty?)' ).must_equal 'arr.filter(item => !(item.length == 0))'
    end

    it "should handle reject(&:nil?)" do
      to_js( 'arr.reject(&:nil?)' ).must_equal 'arr.filter(item => !(item == null))'
    end
  end

  describe "to_sym" do
    it "should remove .to_sym (no-op)" do
      to_js( '"foo".to_sym' ).must_equal '"foo"'
    end

    it "should remove .to_sym in chain" do
      to_js( '"name".downcase.to_sym' ).must_equal '"name".toLowerCase()'
    end
  end

  describe "Class.new { }.new object literal" do
    it "should convert anonymous class instantiation to object literal" do
      to_js_2015( 'Class.new do def foo; 1; end; end.new' ).must_equal '{get foo() {return 1}}'
    end

    it "should handle methods with arguments as shorthand methods" do
      to_js_2015( 'Class.new do def add(a, b); a + b; end; end.new' ).must_equal '{add(a, b) {a + b}}'
    end

    it "should handle getter and setter pairs" do
      to_js_2015( 'Class.new do def foo; @foo; end; def foo=(v); @foo = v; end; end.new' ).
        must_equal '{get foo() {return this._foo}, set foo(v) {this._foo = v}}'
    end

    it "should preserve class syntax when inheritance is used" do
      to_js_2015( 'Class.new(Parent) do def foo; 1; end; end.new' ).
        must_equal 'new class extends Parent {get foo() {return 1}}'
    end

    it "should handle assignment to variable" do
      to_js_2015( 'obj = Class.new do def foo; 1; end; end.new' ).
        must_equal 'let obj = {get foo() {return 1}}'
    end
  end

  describe "Function.new" do
    it "should convert Function.new to regular function" do
      to_js( 'fn = Function.new { |x| x * 2 }' ).
        must_equal 'let fn = function(x) {x * 2}'
    end

    it "should convert Function.new with multiple args" do
      to_js( 'fn = Function.new { |a, b| a + b }' ).
        must_equal 'let fn = function(a, b) {a + b}'
    end

    it "should convert Function.new with no args" do
      to_js( 'fn = Function.new { 42 }' ).
        must_equal 'let fn = function() {42}'
    end

    it "should leave proc as arrow function" do
      to_js( 'fn = proc { |x| x * 2 }' ).
        must_equal 'let fn = x => x * 2'
    end

    it "should leave Proc.new as arrow function" do
      to_js( 'fn = Proc.new { |x| x * 2 }' ).
        must_equal 'let fn = x => x * 2'
    end

    it "should handle next as return inside lambda within for-of loop" do
      to_js( 'items.each { |i| f = lambda { |x| x.any? { |y| next unless y } } }' ).
        must_include 'x.some((y) => {if (!y) return})'
    end
  end
end
