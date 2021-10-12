gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/functions'

describe Ruby2JS::Filter::Functions do

  def to_js(string)
    _(Ruby2JS.convert(string, filters: [Ruby2JS::Filter::Functions]).to_s)
  end

  def to_js_2020(string)
    _(Ruby2JS.convert(string, eslevel: 2020, filters: [Ruby2JS::Filter::Functions]).to_s)
  end

  describe 'conversions' do
    it "should handle to_s" do
      to_js( 'a.to_s' ).must_equal 'a.toString()'
    end

    it "should handle to_s(16)" do
      to_js( 'a.to_s(16)' ).must_equal 'a.toString(16)'
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
        must_equal 'str.replace(/a/, function() {return "x"})'
      to_js( 'str.sub!("a", "b")' ).
        must_equal 'var str = str.replace("a", "b")'
      to_js( 'item.str.sub!("a", "b")' ).
        must_equal 'item.str = item.str.replace("a", "b")'
      to_js( '@str.sub!("a", "b")' ).
        must_equal 'this._str = this._str.replace("a", "b")'
      to_js( '@@str.sub!("a", "b")' ).
        must_equal 'this.constructor._str = this.constructor._str.replace("a", "b")'
      to_js( '$str.sub!("a", "b")' ).
        must_equal 'var $str = $str.replace("a", "b")'
      to_js( 'str.sub!(/a/) {"x"}' ).
        must_equal 'var str = str.replace(/a/, function() {return "x"})'
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
        must_equal 'str.replace(/a/g, function() {return "x"})'
      to_js( 'str.gsub!("a", "b")' ).
        must_equal 'var str = str.replace(/a/g, "b")'
      to_js( 'item.str.gsub!("a", "b")' ).
        must_equal 'item.str = item.str.replace(/a/g, "b")'
      to_js( 'str.gsub!(/a/, "b")' ).
        must_equal 'var str = str.replace(/a/g, "b")'
      to_js( "str.gsub(/a(.)/, 'b\\1')" ).
        must_equal 'str.replace(/a(.)/g, "b$1")'
    end

    it 'should handle scan' do
      to_js( 'str.scan(/\d/)' ).must_equal 'str.match(/\d/g)'
      to_js( 'str.scan(/(\d)(\d)/)' ).
        must_equal '(str.match(/(\d)(\d)/g) || []).map(function(s) {' +
          'return s.match(/(\d)(\d)/).slice(1)})'
      to_js( 'str.scan(pattern)' ).
        must_equal '(str.match(new RegExp(pattern, "g")) || []).' +
          'map(function(s) {return s.match(pattern).slice(1)})'
    end

    it 'should handle sort!' do
      to_js( 'str.sort! {|a, b| a - b}' ).
        must_equal 'str.sort(function(a, b) {return a - b})'

      unless (RUBY_VERSION.split('.').map(&:to_i) <=> [2, 7, 0]) == -1
        to_js( 'str.sort! { _1 - _2}' ).
          must_equal 'str.sort(function(_1, _2) {return _1 - _2})'
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

    it 'should handle start_with?' do
      to_js( 'x.start_with?(y)' ).must_equal 'x.substring(0, y.length) == y'
      to_js( 'x.start_with?("z")' ).must_equal 'x.substring(0, 1) == "z"'
    end

    it 'should handle end_with?' do
      to_js( 'x.end_with?(y)' ).must_equal 'x.slice(-y.length) == y'
      to_js( 'x.end_with?("z")' ).must_equal 'x.slice(-1) == "z"'
    end

    it 'should handle strip/lstrip/rstrip' do
      to_js( 'x.strip()' ).must_equal 'x.trim()'
      to_js( 'x.strip' ).must_equal 'x.trim()'
      to_js( 'a.lstrip()' ).must_equal 'a.replace(/^\s+/, "")'
      to_js( 'a.rstrip()' ).must_equal 'a.replace(/\s+$/, "")'
    end

    it 'should handle string multiply' do
      to_js( '" " * indent' ).must_equal 'new Array(indent + 1).join(" ")'
    end
  end

  describe 'array functions' do
    it "should map each to for statement" do
      to_js( 'a = 0; [1,2,3].each {|i| a += i}').
        must_equal 'var a = 0; [1, 2, 3].forEach(function(i) {a += i})'
    end

    it "should map each_with_index to forEach" do
      to_js( 'a = 0; [1,2,3].each_with_index {|n, i| a += n}').
        must_equal 'var a = 0; [1, 2, 3].forEach(function(n, i) {a += n})'
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

    it "should handle regular expression indexes" do
      to_js( 'a[/\d+/]' ).must_equal '(a.match(/\d+/) || [])[0]'
      to_js( 'a[/(\d+)/, 1]' ).must_equal '(a.match(/(\d+)/) || [])[1]'
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
        'function(match) {d + match[1]})')
      to_js( 'a[/^a(b)c/, 1] = d' ).must_equal(
        'var a = a.replace(/^(a)(b)(c)/m, ' +
        'function(match) {match[0] + d + match[2]})')
    end

    it "should handle empty?" do
      to_js( 'a.empty?' ).must_equal 'a.length == 0'
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
      to_js( 'a.include? b' ).must_equal 'a.indexOf(b) != -1'
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
        must_equal 'a.some(function(i) {return i == 0})'
    end

    it "should handle map" do
      to_js( 'a.map {|i| i+1}' ).
        must_equal 'a.map(function(i) {return i + 1})'
    end

    it "should handle find" do
      to_js( 'a.find {|i| i<0}' ).
        must_equal 'a.find(function(i) {return i < 0})'
    end

    it "should handle find_index" do
      to_js( 'a.find_index {|i| i<0}' ).
        must_equal 'a.findIndex(function(i) {return i < 0})'
    end

    it "should handle all?" do
      to_js( 'a.all? {|i| i==0}' ).
        must_equal 'a.every(function(i) {return i == 0})'
    end

    it "should handle max" do
      to_js( 'a.max' ).must_equal 'a.max'
      to_js( 'a.max()' ).must_equal 'Math.max.apply(Math, a)'
      to_js( '[a,b].max' ).must_equal 'Math.max(a, b)'
    end

    it "should handle min" do
      to_js( 'a.min' ).must_equal 'a.min'
      to_js( 'a.min()' ).must_equal 'Math.min.apply(Math, a)'
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
      to_js( 'a.sum' ).must_equal 'a.reduce(function(a, b) {a + b}, 0)'
    end

    it "should map .select to .filter" do
      to_js( 'a.select {|item| item > 0}' ).
        must_equal 'a.filter(function(item) {return item > 0})'
    end

    it "should map .select! to .splice(0, .length, .filter)" do
      to_js( 'a.select! {|item| item > 0}' ).
        must_equal 'a.splice.apply(a, [0, a.length].concat(a.filter(function(item) {return item > 0})))'
    end

    it "should map .map! to .splice(0, .length, .map)" do
      to_js( 'a.map! {|item| -item}' ).
        must_equal 'a.splice.apply(a, [0, a.length].concat(a.map(function(item) {return -item})))'
    end

    it "should map .reverse! to .splice(0, .length, .reverse)" do
      to_js( 'a.reverse!()' ).
        must_equal 'a.splice.apply(a, [0, a.length].concat(a.reverse()))'
    end

    it "should map Array(foo) to Array.prototype.slice.call(foo)" do
      to_js( 'Array(foo)' ).
        must_equal 'Array.prototype.slice.call(foo)'
    end
  end

  describe 'hash functions' do
    it "should map each_pair to Object.keys().forEach, extracting values" do
      to_js( 'h.each_pair {|key, i| a += i}').
        must_equal 'for (var key in h) {var i = h[key]; a += i}'
    end

    it "should map each_value to Object.keys().forEach, extracting values" do
      to_js( 'h.each_value {|i| a += i}').
        must_equal 'h.forEach(function(i) {a += i})'
    end

    it "should handle keys" do
      to_js( 'a.keys' ).must_equal 'a.keys'
      to_js( 'a.keys()' ).must_equal 'Object.keys(a)'
    end

    it "should convert hash.each_key" do
      to_js( 'h.each_key {|k| x+=k}' ).
        must_equal 'for (var k in h) {x += k}'
    end

    it "should handle merge" do
      to_js( 'b={}; a = a.merge(b)' ).
        must_equal  "var b = {}; var a = function() {var $$ = {}; " +
          "for (var $_ in a) {$$[$_] = a[$_]}; " +
          "for (var $_ in b) {$$[$_] = b[$_]}; return $$}()"
    end

    it "should handle merge with a constant hash" do
      # simple LHS
      to_js( 'a = a.merge(b: 1)' ).
        must_equal  "var a = function() {var $$ = {}; " +
          "for (var $_ in a) {$$[$_] = a[$_]}; " +
          "$$.b = 1; return $$}()"

      # computed LHS
      to_js( 'a.b.merge(b: 1)' ).
        must_equal  "function() {var $$ = {}; " +
          "var $1 = a.b; Object.defineProperties($$, " +
          "Object.getOwnPropertyNames($1).reduce(function($2, $3) {" +
          "$2[$3] = Object.getOwnPropertyDescriptor($1, $3); return $2}, " +
          "{})); $$.b = 1}()"
    end

    it "should handle merge!" do
      to_js( 'b={}; a.merge!(b)' ).
        must_equal "var b = {}; for (var $_ in b) {a[$_] = b[$_]}"
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
        must_equal 'HTTP.delete("x", function() {})'
    end

    it "should not map delete chains" do
      to_js( 'HTTP.delete("x").then {}' ).
        must_equal 'HTTP.delete("x").then(function() {})'
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
        must_equal 'for (var i = 1; i <= 3; i++) {p(i)}'
    end

    it "should map downto to for" do
      to_js( '3.downto(1) {|i| p i}' ).
        must_equal 'for (var i = 3; i >= 1; i--) {p(i)}'
    end

    it "should range each to for" do
      to_js( '(1..10).each {|i| p i}' ).
        must_equal 'for (var i = 1; i <= 10; i++) {p(i)}'
      to_js( '(1...10).each {|i| p i}' ).
        must_equal 'for (var i = 1; i < 10; i++) {p(i)}'
    end

    it "should map step().each to for -- default" do
      to_js( '1.step(3).each {|i| p i}' ).
        must_equal 'for (var i = 1; i <= 3; i++) {p(i)}'
    end

    it "should map step().each to for -- forward" do
      to_js( '1.step(3, 2).each {|i| p i}' ).
        must_equal 'for (var i = 1; i <= 3; i += 2) {p(i)}'
    end

    it "should map step().each to for -- reverse" do
      to_js( '5.step(1, -2).each {|i| p i}' ).
        must_equal 'for (var i = 5; i >= 1; i -= 2) {p(i)}'
    end
  end

  describe 'setTimeout/setInterval' do
    it "should handle setTimeout with first parameter passed as a block" do
      to_js( 'setInterval(100) {x()}' ).
        must_equal 'setInterval(function() {x()}, 100)'
    end

    it "should handle snake case" do
      to_js( 'set_interval 100 do; x(); end' ).
        must_equal 'set_interval(function() {x()}, 100)' # to be processed by camelCase
    end

    it "should handle setInterval with first parameter passed as a block" do
      to_js( 'setInterval(100) {x()}' ).
        must_equal 'setInterval(function() {x()}, 100)'
    end
  end

  describe 'block-pass' do
    it 'should handle properties' do
      to_js( 'a.all?(&:ready)' ).
        must_equal 'a.every(function(item) {return item.ready})'
    end

    it 'should handle well known methods' do
      to_js( 'a.map(&:to_i)' ).
        must_equal 'a.map(function(item) {return parseInt(item)})'
    end

    it 'should handle binary operators' do
      to_js( 'a.sort(&:<)' ).
        must_equal 'a.sort(function(a, b) {return a < b})'
    end

    it 'should handle block arguments' do
      to_js( 'a.sort(&b)' ).
        must_equal 'a.sort(b)'
    end

    it 'should handles loops' do
      to_js( 'loop {sleep 1; break}' ).
        must_equal 'while (true) {sleep(1); break}'
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
        must_equal '(function(bar) {console.log(bar); return bar})(foo)'
    end

    it 'should handle yield_self' do
      to_js( 'foo.yield_self {|n| n*n}' ). 
        must_equal '(function(n) {return n * n})(foo)'
    end
  end

  describe "math functions" do
    it "should handle abs" do
      to_js( 'a.abs' ).must_equal 'Math.abs(a)'
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
        must_equal 'var result = expr ? "meth" in a.prototype : a.prototype.hasOwnProperty("meth")'
    end

    it "should handle alias_method" do
      to_js( 'Klass.alias_method :newname, :oldname').must_equal 'Klass.prototype.newname = Klass.prototype.oldname'
      to_js_2020( 'class C; alias_method :c, :d; end').
        must_equal 'class C {}; C.prototype.c = C.prototype.d'
    end

    it "should handle define_method" do
      to_js_2020( 'Klass.define_method(:newname) {|x| return x * 5 }').must_equal 'Klass.prototype.newname = function(x) {return x * 5}'
      to_js_2020( 'Klass.define_method(newname) {|x| return x * 5 }').must_equal 'Klass.prototype[newname] = function(x) {return x * 5}'
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include Functions" do
      _(Ruby2JS::Filter::DEFAULTS).must_include Ruby2JS::Filter::Functions
    end
  end
end
