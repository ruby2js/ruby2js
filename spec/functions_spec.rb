require 'minitest/autorun'
require 'ruby2js/filter/functions'

describe Ruby2JS::Filter::Functions do
  
  def to_js( string)
    Ruby2JS.convert(string, filters: [Ruby2JS::Filter::Functions])
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

    it "should handle to_f" do
      to_js( 'puts "hi"' ).must_equal 'console.log("hi")'
    end
  end

  describe 'string functions' do
    it 'should handle sub' do
      to_js( 'str.sub("a", "b")' ).must_equal 'str.replace("a", "b")'
      to_js( 'str.sub(/a/) {return "x"}' ).
        must_equal 'str.replace(/a/, function() {return "x"})'
    end

    it 'should handle gsub' do
      to_js( 'str.gsub("a", "b")' ).must_equal 'str.replace(/a/g, "b")'
      to_js( 'str.gsub(/a/i, "b")' ).must_equal 'str.replace(/a/gi, "b")'
      to_js( 'str.gsub(/a/, "b")' ).must_equal 'str.replace(/a/g, "b")'
      to_js( 'str.gsub(/a/) {return "x"}' ).
        must_equal 'str.replace(/a/g, function() {return "x"})'
    end

    it 'should handle ord and chr' do
      to_js( '"A".ord' ).must_equal '65'
      to_js( 'a.ord' ).must_equal 'a.charCodeAt(0)'
      to_js( '65.chr' ).must_equal '"A"'
      to_js( 'a.chr' ).must_equal 'String.fromCharCode(a)'
    end
  end
    
  describe 'array functions' do
    it "should map each to forEach" do
      to_js( 'a = 0; [1,2,3].each {|i| a += i}').
        must_equal 'var a = 0; [1, 2, 3].forEach(function(i) {a += i})'
    end

    it "should map each_with_index to forEach" do
      to_js( 'a = 0; [1,2,3].each_with_index {|n, i| a += n}').
        must_equal 'var a = 0; [1, 2, 3].forEach(function(n, i) {a += n})'
    end

    it "should handle first" do
      to_js( 'a.first' ).must_equal 'a[0]'
    end

    it "should handle last" do
      to_js( 'a.last' ).must_equal 'a[a.length - 1]'
    end

    it "should handle literal negative offsets" do
      to_js( 'a[-2]' ).must_equal 'a[a.length - 2]'
    end

    it "should handle inclusive ranges" do
      to_js( 'a[2..4]' ).must_equal 'a.slice(2, 5)'
      to_js( 'a[2..-1]' ).must_equal 'a.slice(2, a.length)'
      to_js( 'a[-4..-2]' ).must_equal 'a.slice(a.length - 4, a.length - 1)'
    end

    it "should handle exclusive ranges" do
      to_js( 'a[2...4]' ).must_equal 'a.slice(2, 4)'
      to_js( 'a[-4...-2]' ).must_equal 'a.slice(a.length - 4, a.length - 2)'
    end

    it "should handle regular expression indexes" do
      to_js( 'a[/\d+/]' ).must_equal 'a.match(/\d+/)[0]'
      to_js( 'a[/(\d+)/, 1]' ).must_equal 'a.match(/(\d+)/)[1]'
    end

    it "should handle empty?" do
      to_js( 'a.empty?' ).must_equal 'a.length == 0'
    end

    it "should handle clear!" do
      to_js( 'a.clear!' ).must_equal 'a.length = 0'
    end

    it "should handle include?" do
      to_js( 'a.include? b' ).must_equal 'a.indexOf(b) != -1'
    end

    it "should handle any?" do
      to_js( 'a.any? {|i| i==0}' ).must_equal 'a.some(function(i) {i == 0})'
    end

    it "should handle all?" do
      to_js( 'a.all? {|i| i==0}' ).must_equal 'a.every(function(i) {i == 0})'
    end
  end

  describe 'setTimeout/setInterval' do
    it "should handle setTimeout with first parameter passed as a block" do
      to_js( 'setInterval(100) {x()}' ).
        must_equal 'setInterval(function() {x()}, 100)'
    end

    it "should handle setInterval with first parameter passed as a block" do
      to_js( 'setInterval(100) {x()}' ).
        must_equal 'setInterval(function() {x()}, 100)'
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include Functions" do
      Ruby2JS::Filter::DEFAULTS.must_include Ruby2JS::Filter::Functions
    end
  end
end
