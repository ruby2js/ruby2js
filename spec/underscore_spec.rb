require 'minitest/autorun'
require 'ruby2js/filter/underscore'

describe Ruby2JS::Filter::Underscore do

  def to_js( string)
    _(Ruby2JS.convert(string, filters: [Ruby2JS::Filter::Underscore]).to_s)
  end

  describe 'pass through direct calls to underscore' do
    it "leave _.where alone" do
      to_js( '_.where(plays, author: "Shakespeare", year: 1611)' ).
        must_equal '_.where(plays, {author: "Shakespeare", year: 1611})'
    end
  end

  describe 'pluck' do
    it "should map 'map' block-pass to 'pluck'" do
      to_js( 'x.map(&:foo)' ).must_equal '_.pluck(x, "foo")'
    end
  end

  describe 'has_key?' do
    it "should map has_key? to _.key" do
      to_js( 'x.has_key? :foo' ).must_equal '_.has(x, "foo")'
    end
  end

  describe 'find, reject, times' do
    it "should map .find to _.find" do
      to_js( 'a.find {|item| item > 0}' ).
        must_equal '_.find(a, item => item > 0)'
    end

    it "should map .reject to _.reject" do
      to_js( 'a.reject {|item| item > 0}' ).
        must_equal '_.reject(a, item => item > 0)'
    end

    it "should map .reject! to .splice(0, .length, *_.reject)" do
      to_js( 'a.reject! {|item| item > 0}' ).
        must_equal 'a.splice(...[0, a.length].concat(_.reject(a, item => item > 0)))'
    end

    it "should map .times to _.times" do
      to_js( '5.times {|i| console.log i}' ).
        must_equal '_.times(5, i => console.log(i))'
    end
  end

  describe 'where, find_by' do
    it "should map .where to _.where" do
      to_js( 'plays.where author: "Shakespeare", year: 1611' ).
        must_equal '_.where(plays, {author: "Shakespeare", year: 1611})'
    end

    it "should map .find_by to _.findWhere" do
      to_js( 'plays.find_by author: "Shakespeare", year: 1611' ).
        must_equal '_.findWhere(plays, {author: "Shakespeare", year: 1611})'
    end
  end

  describe 'sort, sort_by, group_by, index_by, count_by' do
    it "should map .sort to _.sort_by(,_.identity)" do
      to_js( 'x.sort()' ).must_equal '_.sortBy(x, _.identity)'
    end

    it "should map .sort_by to _.sortBy" do
      to_js( 'x.sort_by {|n| -n}' ).
        must_equal '_.sortBy(x, n => -n)'
    end

    it "should map .sort_by to _.sortBy" do
      to_js( 'x.sort_by(&:foo)' ).
        must_equal '_.sortBy(x, item => item.foo)'
    end

    it "should map .sort_by! to .splice(0, .length, *_.sortBy)" do
      to_js( 'a.sort_by! {|item| item > 0}' ).
        must_equal 'a.splice(...[0, a.length].concat(_.sortBy(a, item => item > 0)))'
    end

    it "should map .group_by to _.groupBy" do
      to_js( 'x.group_by(&:foo)' ).
        must_equal '_.groupBy(x, item => item.foo)'
    end

    it "should map .index_by to _.indexBy" do
      to_js( 'x.index_by(&:foo)' ).
        must_equal '_.indexBy(x, item => item.foo)'
    end

    it "should map .count_by to _.countBy" do
      to_js( 'x.count_by(&:foo)' ).
        must_equal '_.countBy(x, item => item.foo)'
    end
  end

  describe 'merge, merge!' do
    it "should map merge to _.extend({}, ...)" do
      to_js( 'a.merge(b)' ).must_equal '_.extend({}, a, b)'
    end

    it "should map merge! to _.extend" do
      to_js( 'a.merge!(b)' ).must_equal '_.extend(a, b)'
    end
  end

  describe 'zip' do
    it "should map zip to _.extend" do
      to_js( 'a.zip(b)' ).must_equal '_.zip(a, b)'
    end
  end

  describe 'range' do
    it "should map erange to _.range" do
      to_js( '(0..9)' ).must_equal '_.range(0, 10)'
      to_js( '(0..n)' ).must_equal '_.range(0, n + 1)'
      to_js( '(0...9)' ).must_equal '_.range(0, 9)'
    end

    it "should handle a for loop with an inclusive range" do
      to_js( 'a = 0; for i in 1..3; a += i; end' ).
        must_equal 'let a = 0; for (let i = 1; i <= 3; i++) {a += i}'
    end

    it "should handle a for loop with an exclusive range" do
      to_js( 'a = 0; for i in 1...4; a += i; end' ).
        must_equal 'let a = 0; for (let i = 1; i < 4; i++) {a += i}'
    end
  end

  describe 'zero argument methods: clone, size, ...' do
    it "should map clone() to _.clone()" do
      to_js( 'a.clone()' ).must_equal '_.clone(a)'
    end

    it "should map shuffle() to _.shuffle()" do
      to_js( 'a.shuffle()' ).must_equal '_.shuffle(a)'
    end

    it "should map shuffle!() to a.splice(0, .length, *_.shuffle())" do
      to_js( 'a.shuffle!()' ).
        must_equal 'a.splice(0, a.length, ..._.shuffle(a))'
    end

    it "should map compact() to _.compact()" do
      to_js( 'a.compact()' ).must_equal '_.compact(a)'
    end

    it "should map compact!() to a.splice(0, .length, *_.compact())" do
      to_js( 'a.compact!()' ).
        must_equal 'a.splice(0, a.length, ..._.compact(a))'
    end

    it "should map flatten() to _.flatten()" do
      to_js( 'a.flatten()' ).must_equal '_.flatten(a)'
    end

    it "should map flatten!() to a.splice(0, .length, *_.flatten())" do
      to_js( 'a.flatten!()' ).
        must_equal 'a.splice(0, a.length, ..._.flatten(a))'
    end

    it "should map invert() to _.invert()" do
      to_js( 'a.invert()' ).must_equal '_.invert(a)'
    end

    it "should map values() to _.values()" do
      to_js( 'a.values()' ).must_equal '_.values(a)'
    end

    it "should map size() to _.size()" do
      to_js( 'a.size()' ).must_equal '_.size(a)'
    end

    it "should map uniq() to _.uniq()" do
      to_js( 'a.uniq()' ).must_equal '_.uniq(a)'
    end

    it "should map uniq!() to a.splice(0, .length, *_.uniq())" do
      to_js( 'a.uniq!()' ).
        must_equal 'a.splice(0, a.length, ..._.uniq(a))'
    end

    it "should not map size" do
      to_js( 'a.size' ).must_equal 'a.size'
    end
  end

  describe 'reduce' do
    it "should map reduce: symbol to _.reduce" do
      to_js( 'a.reduce(:+)' ).
        must_equal '_.reduce(_.rest(a), (memo, item) => memo + item, a[0])'
    end

    it "should map reduce: initial, symbol to _.reduce function, initial" do
      to_js( 'a.reduce(0, :+)' ).
        must_equal '_.reduce(a, (memo, item) => memo + item, 0)'
    end

    it "should map reduce: function to _.reduce" do
      to_js( 'a.reduce {|memo, item| memo + item}' ).
        must_equal '_.reduce(_.rest(a), (memo, item) => memo + item, a[0])'
    end

    it "should map reduce: initial, function to _.reduce function, initial" do
      to_js( 'a.reduce(0) {|memo, item| memo + item}' ).
        must_equal '_.reduce(a, (memo, item) => memo + item, 0)'
    end

    it "should map reduce: block-pass to _.reduce" do
      to_js( 'a.reduce(&:+)' ).
        must_equal '_.reduce(_.rest(a), (memo, item) => memo + item, a[0])'
    end
  end

  describe 'take, drop' do
    it "should map take: number to _.take" do
      to_js( 'a.take(5)' ).must_equal '_.take(a, 5)'
    end

    it "should map drop: number to _.drop" do
      to_js( 'a.drop(5)' ).must_equal '_.drop(a, 5)'
    end
  end

  describe 'min, max' do
    it "should map min to _.min" do
      to_js( 'a.min' ).must_equal '_.min(a)'
    end

    it "should map max to _.max" do
      to_js( 'a.max' ).must_equal '_.max(a)'
    end
  end

  describe 'each_slice' do
    it "should map each_slice: number to _.chunk" do
      to_js( 'a.each_slice(7)' ).must_equal '_.chunk(a, 7)'
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include Underscore" do
      _(Ruby2JS::Filter::DEFAULTS).must_include Ruby2JS::Filter::Underscore
    end
  end
end
