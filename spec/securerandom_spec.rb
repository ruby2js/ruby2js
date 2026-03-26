require 'minitest/autorun'
require 'ruby2js/filter/securerandom'

describe Ruby2JS::Filter::SecureRandom do

  def to_js(string)
    _(Ruby2JS.convert(string, filters: [Ruby2JS::Filter::SecureRandom]).to_s)
  end

  describe 'uuid' do
    it 'should generate crypto.randomUUID()' do
      to_js('SecureRandom.uuid').must_equal 'crypto.randomUUID()'
    end
  end

  describe 'alphanumeric' do
    it 'should generate helper function call with default length' do
      result = Ruby2JS.convert('SecureRandom.alphanumeric',
        filters: [Ruby2JS::Filter::SecureRandom]).to_s
      _(result).must_include '_secureRandomAlphanumeric(16)'
      _(result).must_include 'function _secureRandomAlphanumeric'
    end

    it 'should generate helper function call with specified length' do
      result = Ruby2JS.convert('SecureRandom.alphanumeric(12)',
        filters: [Ruby2JS::Filter::SecureRandom]).to_s
      _(result).must_include '_secureRandomAlphanumeric(12)'
    end
  end

  describe 'hex' do
    it 'should generate helper function call with default length' do
      result = Ruby2JS.convert('SecureRandom.hex',
        filters: [Ruby2JS::Filter::SecureRandom]).to_s
      _(result).must_include '_secureRandomHex(16)'
      _(result).must_include 'function _secureRandomHex'
    end

    it 'should generate helper function call with specified length' do
      result = Ruby2JS.convert('SecureRandom.hex(8)',
        filters: [Ruby2JS::Filter::SecureRandom]).to_s
      _(result).must_include '_secureRandomHex(8)'
    end
  end

  describe 'random_number' do
    it 'should generate random float without arguments' do
      to_js('SecureRandom.random_number').
        must_include 'getRandomValues'
    end

    it 'should generate bounded random integer with argument' do
      to_js('SecureRandom.random_number(100)').
        must_include '_secureRandomNumber(100)'
    end
  end

  describe 'base64' do
    it 'should generate helper function call' do
      result = Ruby2JS.convert('SecureRandom.base64',
        filters: [Ruby2JS::Filter::SecureRandom]).to_s
      _(result).must_include '_secureRandomBase64(16)'
      _(result).must_include 'function _secureRandomBase64'
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include SecureRandom" do
      _(Ruby2JS::Filter::DEFAULTS).must_include Ruby2JS::Filter::SecureRandom
    end
  end
end
