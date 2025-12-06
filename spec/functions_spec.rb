gem 'minitest'
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

    it "should handle to_f" do
      to_js( 'a.to_f' ).must_equal 'parseFloat(a)'
    end

    it "should handle puts" do
      to_js( 'puts "hi"' ).must_equal 'console.log("hi")'
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
  end

  describe :irange do
    it "(0..5).to_a" do
      to_js( '(0..5).to_a' ).must_equal('Array.apply(null, {length: 6}).map(Function.call, Number)')
    end

    it "(0..a).to_a" do
      to_js( '(0..a).to_a' ).must_equal('Array.apply(null, {length: a+1}).map(Function.call, Number)')
    end

    it "(b..a).to_a" do
      to_js( '(b..a).to_a' ).must_equal('Array.apply(null, {length: (a-b+1)}).map(Function.call, Number).map(function (idx) { return idx+b })')
    end
  end

  describe :erange do
    it "(0...5).to_a" do
      to_js( '(0...5).to_a' ).must_equal('Array.apply(null, {length: 5}).map(Function.call, Number)')
    end

    it "(0...a).to_a" do
      to_js( '(0...a).to_a' ).must_equal('Array.apply(null, {length: a}).map(Function.call, Number)')
    end

    it "(b...a).to_a" do
      to_js( '(b...a).to_a' ).must_equal('Array.apply(null, {length: (a-b)}).map(Function.call, Number).map(function (idx) { return idx+b })')
    end

    it "test range which contains reserved variable idx" do
      to_js( '(idx...i).to_a' ).must_equal('Array.apply(null, {length: (i-idx)}).map(Function.call, Number).map(function (i$) { return i$+idx })')
    end
  end

  describe 'string functions' do
    it 'should handle sub' do
      to_js( 'str.sub("a", "b")' ).must_equal 'str.replace("a", "b")'
      to_js( 'str.sub(/a/) {"x"}' ).
        must_equal 'str.replace(/a/, () => {return "x"})'
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
        must_equal 'let str = str.replace(/a/, () => {return "x"})'
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
        must_equal 'str.replace(/a/g, () => {return "x"})'
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
        must_equal '(str.match(/(\d)(\d)/g) || []).map((s) => {' +
          'return s.match(/(\d)(\d)/).slice(1)})'
      to_js( 'str.scan(pattern)' ).
        must_equal '(str.match(new RegExp(pattern, "g")) || []).' +
          'map((s) => {return s.match(pattern).slice(1)})'
    end

    it 'should handle sort!' do
      to_js( 'str.sort! {|a, b| a - b}' ).
        must_equal 'str.sort((a, b) => {return a - b})'

      unless (RUBY_VERSION.split('.').map(&:to_i) <=> [2, 7, 0]) == -1
        to_js( 'str.sort! { _1 - _2}' ).
          must_equal 'str.sort((_1, _2) => {return _1 - _2})'
      end
    end

    it 'should handle ord and chr' do
      to_js( '"A".ord' ).must_equal '65'
      to_js( 'a.ord' ).must_equal 'a.charCodeAt(0)'
      to_js( '65.chr' ).must_equal '"A"'
      to_js( 'a.chr' ).must_equal 'String.fromCharCode(a)'
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
    end

    it 'should handle end_with?' do
      to_js( 'x.end_with?(y)' ).must_equal "x.endsWith(y)"
      to_js( 'x.end_with?("z")' ).must_equal "x.endsWith(\"z\")"
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
  end

  describe 'array functions' do
    it "should map each to for statement" do
      to_js( 'a = 0; [1,2,3].each {|i| a += i}').
        must_equal 'let a = 0; [1, 2, 3].forEach((i) => {a += i})'
    end

    it "should map each_with_index to forEach" do
      to_js( 'a = 0; [1,2,3].each_with_index {|n, i| a += n}').
        must_equal 'let a = 0; [1, 2, 3].forEach((n, i) => {a += n})'
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

    it "should handle range assignment" do
      to_js_2015( 'a[0..2] = v' ).must_equal 'a.splice(0, 2 - 0 + 1, ...v)'
      to_js_2015( 'a[0...2] = v' ).must_equal 'a.splice(0, 2 - 0, ...v)'
      to_js_2015( 'a[1..-1] = v' ).must_equal 'a.splice(1, a.length - 1, ...v)'
    end

    it "should handle regular expression indexes" do
      to_js( 'a[/\d+/]' ).must_equal "a.match(/\d+/)?.[0]"
      to_js( 'a[/(\d+)/, 1]' ).must_equal "a.match(/(\d+)/)?.[1]"
    end

    it "should handle regular expression index assignment" do
      to_js( 'a[/a(b)/, 1] = "d"' ).must_equal(
        'var a = a.replace(/(a)(b)/, "$1d")')
      to_js( 'a[/a(b)c/, 1] = "d"' ).must_equal(
        'var a = a.replace(/(a)(b)(c)/, "$1d$3")')
      to_js( 'a[/a()c/, 1] = "d"' ).must_equal(
        'var a = a.replace(/(a)(c)/, "$1d$2")')
      to_js( 'a[/(b)c/, 1] = "#{d}"' ).must_equal(
        'var a = a.replace(/(b)(c)/, ' +
        '(match) => {d + match[1]})')
      to_js( 'a[/^a(b)c/, 1] = d' ).must_equal(
        'var a = a.replace(/^(a)(b)(c)/m, ' +
        '(match) => {match[0] + d + match[2]})')
    end

    it "should handle empty?" do
      to_js( 'a.empty?' ).must_equal 'a.length == 0'
    end

    it "should handle empty? with safe navigation" do
      to_js_2020( 'a&.empty?' ).must_equal 'a?.length == 0'
    end

    it "should handle nil?" do
      to_js( 'a.nil?' ).must_equal 'a == null'
    end

    it "should handle clear" do
      to_js( 'a.clear()' ).must_equal 'a.length = 0'
    end

    it "should handle replace" do
      to_js( 'a.replace(b)' ).
        must_equal 'a.length = 0; a.push.apply(a, b)'
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
    end

    it "should handle any?" do
      to_js( 'a.any? {|i| i==0}' ).
        must_equal 'a.some((i) => {return i == 0})'
    end

    it "should handle map" do
      to_js( 'a.map {|i| i+1}' ).
        must_equal 'a.map((i) => {return i + 1})'
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
        must_equal 'a.find((i) => {return i < 0})'
    end

    it "should handle find_index" do
      to_js( 'a.find_index {|i| i<0}' ).
        must_equal 'a.findIndex((i) => {return i < 0})'
    end

    it "should handle index with block" do
      to_js( 'a.index {|i| i<0}' ).
        must_equal 'a.findIndex((i) => {return i < 0})'
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
        must_equal 'a.every((i) => {return i == 0})'
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

    it "should map .select to .filter" do
      to_js( 'a.select {|item| item > 0}' ).
        must_equal 'a.filter((item) => {return item > 0})'
    end

    it "should map .select! to .splice(0, .length, .filter)" do
      to_js( 'a.select! {|item| item > 0}' ).
        must_equal 'a.splice.apply(a, [0, a.length].concat(a.filter((item) => {return item > 0})))'
    end

    it "should map .map! to .splice(0, .length, .map)" do
      to_js( 'a.map! {|item| -item}' ).
        must_equal 'a.splice.apply(a, [0, a.length].concat(a.map((item) => {return -item})))'
    end

    it "should map .reverse! to .splice(0, .length, .reverse)" do
      to_js( 'a.reverse!()' ).
        must_equal 'a.splice.apply(a, [0, a.length].concat(a.reverse()))'
    end

    it "should map Array(foo) to Array.prototype.slice.call(foo)" do
      to_js( 'Array(foo)' ).
        must_equal 'Array.prototype.slice.call(foo)'
    end

    it "should map Array.new with two args to fill" do
      to_js_2020( 'Array.new(5, 1)').
        must_equal 'new Array(5).fill(1)'
    end
  end

  describe 'hash functions' do
    it "should map each_pair to Object.keys().forEach, extracting values" do
      to_js( 'h.each_pair {|key, i| a += i}').
        must_equal 'for (let key in h) {var i = h[key]; a += i}'
    end

    it "should map each_value to Object.keys().forEach, extracting values" do
      to_js( 'h.each_value {|i| a += i}').
        must_equal 'h.forEach((i) => {a += i})'
    end

    it "should handle keys" do
      to_js( 'a.keys' ).must_equal 'a.keys'
      to_js( 'a.keys()' ).must_equal 'Object.keys(a)'
    end

    it "should convert hash.each_key" do
      to_js( 'h.each_key {|k| x+=k}' ).
        must_equal 'for (let k in h) {x += k}'
    end

    it "should handle merge" do
      to_js( 'b={}; a = a.merge(b)' ).
        must_equal  "var b = {}; var a = () => {var $$ = {}; " +
          "for (let $_ in a) {$$[$_] = a[$_]}; " +
          "for (let $_ in b) {$$[$_] = b[$_]}; return $$}()"
    end

    it "should handle merge with a constant hash" do
      # simple LHS
      to_js( 'a = a.merge(b: 1)' ).
        must_equal  "var a = () => {var $$ = {}; " +
          "for (let $_ in a) {$$[$_] = a[$_]}; " +
          "$$.b = 1; return $$}()"

      # computed LHS
      to_js( 'a.b.merge(b: 1)' ).
        must_equal  "() => {var $$ = {}; " +
          "var $1 = a.b; Object.defineProperties($$, " +
          "Object.getOwnPropertyNames($1).reduce(($2, $3) => {" +
          "$2[$3] = Object.getOwnPropertyDescriptor($1, $3); return $2}, " +
          "{})); $$.b = 1}()"
    end

    it "should handle merge!" do
      to_js( 'b={}; a.merge!(b)' ).
        must_equal "let b = {}; for (let $_ in b) {a[$_] = b[$_]}"
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
    it "should map is_a?" do
      to_js( 'true.is_a? Boolean' ).
        must_equal 'Object.prototype.toString.call(true) === ' +
                   '"[object Boolean]"'
    end

    it "should map kind_of?" do
      to_js( '/a/.kind_of? RegExp' ).
        must_equal 'Object.prototype.toString.call(/a/) === ' +
                   '"[object RegExp]"'
    end

    it "should map kind_of? Array" do
      to_js( '[3].kind_of? Array' ).
        must_equal 'Array.isArray([3])'
    end

    it "should map kind_of? Float" do
      to_js( '3.2.kind_of? Float' ).
        must_equal 'Object.prototype.toString.call(3.2) === ' +
                   '"[object Number]"'
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
        must_equal 'setInterval(() => {x()}, 100)'
    end

    it "should handle snake case" do
      to_js( 'set_interval 100 do; x(); end' ).
        must_equal 'set_interval(() => {x()}, 100)' # to be processed by camelCase
    end

    it "should handle setInterval with first parameter passed as a block" do
      to_js( 'setInterval(100) {x()}' ).
        must_equal 'setInterval(() => {x()}, 100)'
    end
  end

  describe 'block-pass' do
    it 'should handle properties' do
      to_js( 'a.all?(&:ready)' ).
        must_equal 'a.every((item) => {return item.ready})'
    end

    it 'should handle well known methods' do
      to_js( 'a.map(&:to_i)' ).
        must_equal 'a.map((item) => {return parseInt(item)})'
    end

    it 'should handle binary operators' do
      to_js( 'a.sort(&:<)' ).
        must_equal 'a.sort((a, b) => {return a < b})'
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
  end

  describe 'Exceptions' do
    it 'should throw new Error' do
      to_js( 'raise Exception.new("foo")' ). 
        must_equal 'throw new Error("foo")'
    end

    it 'should create an Exception contructor' do
      to_js( 'class E < Exception; end' ).
        must_equal 'function E(message) {this.message = message; ' +
          'this.name = "E"; this.stack = Error(message).stack}; ' +
          'E.prototype = Object.create(Error.prototype); E.prototype.constructor = E'
    end
  end

  describe "tap and yield_self" do
    it 'should handle tap' do
      to_js( 'foo.tap {|bar| puts bar}' ). 
        must_equal '((bar) => {console.log(bar); return bar})(foo)'
    end

    it 'should handle yield_self' do
      to_js( 'foo.yield_self {|n| n*n}' ). 
        must_equal '((n) => {return n * n})(foo)'
    end
  end

  describe "sort_by, max_by, min_by" do
    it "should handle sort_by" do
      to_js( 'a.sort_by { |x| x.name }' ).
        must_equal 'a.slice().sort((x_a, x_b) => {if (x_a.name < x_b.name) {return -1} else if (x_a.name > x_b.name) {return 1} else {return 0}})'
    end

    it "should handle max_by" do
      to_js( 'a.max_by { |x| x.score }' ).
        must_equal 'a.reduce((a, b) => {return a.score >= b.score ? a : b})'
    end

    it "should handle min_by" do
      to_js( 'a.min_by { |x| x.score }' ).
        must_equal 'a.reduce((a, b) => {return a.score <= b.score ? a : b})'
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
      to_js_2020( 'Klass.define_method(:newname) {|x| return x * 5 }').must_equal 'Klass.prototype.newname = (x) => {return x * 5}'
      to_js_2020( 'Klass.define_method(newname) {|x| return x * 5 }').must_equal 'Klass.prototype[newname] = (x) => {return x * 5}'
      # define_method without receiver inside class body
      to_js_2020( 'class Klass; define_method(:foo) {|x| x + 1}; end').
        must_equal 'class Klass {}; Klass.prototype.foo = (x) => {x + 1}'
      # define_method with block variable (inside method body)
      to_js_2020( 'define_method(:foo, myblock)').
        must_equal 'this.constructor.prototype.foo = myblock'
      to_js_2020( 'define_method(name, myblock)').
        must_equal 'this.constructor.prototype[name] = myblock'
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
end
