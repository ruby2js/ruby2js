gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/rubyjs'

describe Ruby2JS::Filter::RubyJS do
  
  def to_js( string)
    Ruby2JS.convert(string, filters: [Ruby2JS::Filter::RubyJS]).to_s
  end
  
  describe 'String conversions' do
    it "should handle capitalize" do
      to_js( 'a.capitalize()' ).must_equal '_s.capitalize(a)'
    end

    it "should handle center" do
      to_js( 'a.center(80)' ).must_equal '_s.center(a, 80)'
    end

    it "should handle chomp" do
      to_js( 'a.chomp()' ).must_equal '_s.chomp(a)'
    end

    it "should handle ljust" do
      to_js( 'a.ljust(80)' ).must_equal '_s.ljust(a, 80)'
    end

    it "should handle lstrip" do
      to_js( 'a.ljust()' ).must_equal '_s.ljust(a)'
    end

    it "should handle rindex" do
      to_js( 'a.rindex("b")' ).must_equal '_s.rindex(a, "b")'
    end

    it "should handle rjust" do
      to_js( 'a.rjust(80)' ).must_equal '_s.rjust(a, 80)'
    end

    it "should handle rstrip" do
      to_js( 'a.rjust()' ).must_equal '_s.rjust(a)'
    end

    it "should handle scan" do
      to_js( 'a.scan(/f/)' ).must_equal '_s.scan(a, /f/)'
    end

    it "should handle swapcase" do
      to_js( 'a.swapcase()' ).must_equal '_s.swapcase(a)'
    end

    it "should handle tr" do
      to_js( 'a.tr("a", "A")' ).must_equal '_s.tr(a, "a", "A")'
    end
  end

  describe 'Array conversions' do
    it "should handle at" do
      to_js( 'a.at(3)' ).must_equal '_a.at(a, 3)'
    end

    it "should handle compact" do
      to_js( 'a.compact' ).must_equal '_a.compact(a)'
    end

    it "should handle compact!" do
      to_js( 'a.compact!' ).must_equal '_a.compact_bang(a)'
    end

    it "should handle delete_at" do
      to_js( 'a.delete_at(3)' ).must_equal '_a.delete_at(a, 3)'
    end

    it "should handle delete_if" do
      to_js( 'a.delete_if {|i| i<0}' ).
        must_equal '_e.delete_if(a, function(i) {return i < 0})'
    end

    it "should handle each_index" do
      to_js( 'a.each_index {|i| a[i]+=1}' ).
        must_equal '_a.each_index(a, function(i) {a[i]++})'
    end

    it "should handle flatten" do
      to_js( 'a.flatten' ).must_equal '_a.flatten(a)'
    end

    it "should handle insert" do
      to_js( 'a.insert(i,3)' ).must_equal '_a.insert(a, i, 3)'
    end

    it "should handle keep_if" do
      to_js( 'a.keep_if {|i| i<0}' ).
        must_equal '_a.keep_if(a, function(i) {return i < 0})'
    end

    it "should handle reverse" do
      to_js( 'a.reverse' ).must_equal '_a.reverse(a)'
    end

    it "should handle reverse!" do
      to_js( 'a.reverse!' ).must_equal '_a.reverse_bang(a)'
    end

    it "should handle rotate" do
      to_js( 'a.rotate(3)' ).must_equal '_a.rotate(a, 3)'
    end

    it "should handle rotate!" do
      to_js( 'a.rotate!(3)' ).must_equal '_a.rotate_bang(a, 3)'
    end

    it "should handle select" do
      to_js( 'a.select! {|i| i<0}' ).
        must_equal '_a.select_bang(a, function(i) {return i < 0})'
    end

    it "should handle shift" do
      to_js( 'a.shift(3)' ).must_equal '_a.shift(a, 3)'
    end

    it "should handle shuffle" do
      to_js( 'a.shuffle' ).must_equal '_a.shuffle(a)'
    end

    it "should handle shuffle!" do
      to_js( 'a.shuffle!' ).must_equal '_a.shuffle_bang(a)'
    end

    it "should handle slice" do
      to_js( 'a.slice(i, 3)' ).must_equal '_a.slice(a, i, 3)'
    end

    it "should handle slice!" do
      to_js( 'a.slice!(i, 3)' ).must_equal '_a.slice_bang(a, i, 3)'
    end

    it "should handle transpose" do
      to_js( 'a.transpose' ).must_equal '_a.transpose(a)'
    end

    it "should handle uniq" do
      to_js( 'a.uniq' ).must_equal '_a.uniq(a)'
    end

    it "should handle uniq_bang" do
      to_js( 'a.uniq!' ).must_equal '_a.uniq_bang(a)'
    end

    it "should handle union" do
      to_js( 'a.union(b)' ).must_equal '_a.union(a, b)'
    end
  end

  describe 'Enumerable conversions' do
    it "should handle collect_concat" do
      to_js( 'a.collect_concat {|i| i}' ).
        must_equal '_e.collect_concat(a, function(i) {return i})'
    end

    it "should handle count" do
      to_js( 'a.count {|i| i % 2 == 0}' ).
        must_equal '_e.count(a, function(i) {return i % 2 == 0})'
    end

    it "should handle drop_while" do
      to_js( 'a.drop_while {|i| i < 3}' ).
        must_equal '_e.drop_while(a, function(i) {return i < 3})'
    end

    it "should handle each_slice" do
      to_js( 's.each_slice(2) {|a,b| console.log [a,b]}' ).
        must_equal '_e.each_slice(s, 2, function(a, b) {console.log([a, b])})'
    end

    it "should handle each_with_index" do
      to_js( 's.each_with_index {|a,i| console.log [a,i]}' ).
        must_equal '_e.each_with_index(s, function(a, i) {console.log([a, i])})'
    end

    it "should handle each_with_object" do
      to_js( 's.each_with_object(a) {|a,b| a << b}' ).
        must_equal '_e.each_with_object(s, a, function(a, b) {a.push(b)})'
    end

    it "should handle find" do
      to_js( 's.find(ifnone) {|a| a < 10}' ).
        must_equal '_e.find(s, ifnone, function(a) {return a < 10})'

      to_js( 's.find {|a| a < 10}' ).
        must_equal '_e.find(s, null, function(a) {return a < 10})'
    end

    it "should handle find_all" do
      to_js( 's.find_all {|a| a < 10}' ).
        must_equal '_e.find_all(s, function(a) {return a < 10})'
    end

    it "should handle flat_map" do
      to_js( 'a.flat_map {|i| i}' ).
        must_equal '_e.flat_map(a, function(i) {return i})'
    end

    it "should handle inject" do
      to_js( 'a.inject(init) {|i,v| i << v}' ).
        must_equal '_e.inject(a, init, null, function(i, v) {i.push(v)})'
    end

    it "should handle grep" do
      to_js( 'a.grep {|s| s =~ /x/}' ).
        must_equal '_e.grep(a, function(s) {return /x/.test(s)})'
    end

    it "should handle group_by" do
      to_js( 'a.group_by {|s| s.name}' ).
        must_equal '_e.group_by(a, function(s) {return s.name})'
    end

    it "should handle map" do
      to_js( 'a.map {|s| s.name}' ).
        must_equal '_e.map(a, function(s) {return s.name})'
    end

    it "should handle max_by" do
      to_js( 'a.max_by {|s| s.name}' ).
        must_equal '_e.max_by(a, function(s) {return s.name})'
    end

    it "should handle min_by" do
      to_js( 'a.min_by {|s| s.name}' ).
        must_equal '_e.min_by(a, function(s) {return s.name})'
    end

    it "should handle one?" do
      to_js( 'a.one? {|s| s < 0}' ).
        must_equal '_e.one(a, function(s) {return s < 0})'
    end

    it "should handle partition" do
      to_js( 'a.partition {|s| s > 0}' ).
        must_equal '_e.partition(a, function(s) {return s > 0})'
    end

    it "should handle reject" do
      to_js( 'a.reject {|s| s < 0}' ).
        must_equal '_e.reject(a, function(s) {return s < 0})'
    end

    it "should handle reverse_each" do
      to_js( 'a.reverse_each {|s| console.log s}' ).
        must_equal '_e.reverse_each(a, function(s) {console.log(s)})'
    end

    it "should handle sort_by" do
      to_js( 'a.sort_by {|s| s.age}' ).
        must_equal '_e.sort_by(a, function(s) {return s.age})'
    end

    it "should handle take_while" do
      to_js( 'a.take_while {|s| s < 0}' ).
        must_equal '_e.take_while(a, function(s) {return s < 0})'
    end
  end

  describe 'Time conversions' do
    it "should handle strftime" do
      to_js( 'Date.new().strftime("%Y")' ).
        must_equal '_t.strftime(new Date(), "%Y")'
    end
  end

  describe 'Comparable conversions' do
    it "should handle <=>" do
      to_js( '3 <=> 5' ).must_equal 'R.Comparable.cmp(3, 5)'
    end

    it "should between?" do
      to_js( '3.between?(1,5)' ).must_equal 'R(3).between(1, 5)'
    end
  end

  describe 'ranges' do
    it "should handle inclusive ranges" do
      to_js( '(1..9)' ).must_equal 'new R.Range(1, 9)'
    end

    it "should handle enclusive ranges" do
      to_js( '(1...9)' ).must_equal 'new R.Range(1, 9, true)'
    end
  end

  describe 'filter bypass operations' do
    it 'should handle functional style calls' do
      to_js( '_s.capitalize("foo")').must_equal  '_s.capitalize("foo")'
    end

    it 'should leave alone classic ("OO") style chains' do
      to_js( 'R("a").capitalize().lstrip()' ).
        must_equal( 'R("a").capitalize().lstrip()' )
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include Functions" do
      Ruby2JS::Filter::DEFAULTS.must_include Ruby2JS::Filter::Functions
    end
  end
end
