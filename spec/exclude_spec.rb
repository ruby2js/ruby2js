gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/functions'

describe 'Ruby2JS::Filter.exclude' do
  
  def to_js( string, options={} )
    Ruby2JS.convert(string, 
     options.merge(filters: [Ruby2JS::Filter::Functions])).to_s
  end
  
  describe 'default exclude' do
    it "should default to NOT mapping class to constructor" do
      to_js( 'a.class' ).must_equal 'a.class'
    end

    it "should be able to OPT IN to mapping class to constructor" do
      to_js( 'a.class', include: :class ).must_equal 'a.constructor'
    end

    it "should be able to OPT IN to all mappings" do
      to_js( 'a.class', include_all: true ).must_equal 'a.constructor'
    end
  end
  
  describe 'explicit exclude - send' do
    it "should default to mapping to_s to toString" do
      to_js( 'a.to_s' ).must_equal 'a.toString()'
    end

    it "should be able to OPT OUT of mapping to_s to toString" do
      to_js( 'a.to_s', exclude: :to_s ).must_equal 'a.to_s'
    end
  end
  
  describe 'explicit exclude - block' do
    it "should default to mapping for setInterval" do
      to_js( 'setInterval(500) {nil}' ).
        must_equal 'setInterval(function() {null}, 500)'
    end

    it "should be able to OPT OUT of setInterval mapping" do
      to_js( 'setInterval(500) {nil}', exclude: :setInterval ).
        must_equal 'setInterval(500, function() {null})'
    end
  end
end
