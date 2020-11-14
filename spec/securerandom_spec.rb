gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/securerandom'
require 'ruby2js/filter/esm'

describe Ruby2JS::Filter::SecureRandom do
  
  def to_js_cjs( string)
    _(Ruby2JS.convert(string, filters: [Ruby2JS::Filter::SecureRandom],
      module: :cjs).to_s)
  end
  
  def to_js_esm( string)
    _(Ruby2JS.convert(string, filters: [Ruby2JS::Filter::SecureRandom]).to_s)
  end
  
  describe 'alphanumeric' do
    it 'should support cjs' do
      to_js_cjs( 'SecureRandom.alphanumeric(10)' ).
        must_equal 'var base62_random = require("base62-random"); ' +
        'base62_random(10)'
    end

    it 'should support esm' do
      to_js_esm( 'SecureRandom.alphanumeric(10)' ).
        must_equal 'import base62_random from "base62-random"; ' +
        'base62_random(10)'
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include SecureRandom" do
      _(Ruby2JS::Filter::DEFAULTS).must_include Ruby2JS::Filter::SecureRandom
    end
  end
end
