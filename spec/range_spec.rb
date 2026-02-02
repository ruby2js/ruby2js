require 'minitest/autorun'
require 'ruby2js'

describe 'Range Converter' do
  def to_js(string, options = {})
    Ruby2JS.convert(string, options).to_s
  end

  describe 'standalone ranges' do
    it 'should convert inclusive range to $Range' do
      js = to_js('r = 1..10')
      _(js).must_include 'new $Range(1, 10)'
      _(js).wont_include 'true'
    end

    it 'should convert exclusive range to $Range with excludeEnd' do
      js = to_js('r = 1...10')
      _(js).must_include 'new $Range(1, 10, true)'
    end

    it 'should convert endless inclusive range' do
      js = to_js('r = 1..')
      _(js).must_include 'new $Range(1, null)'
      _(js).wont_include 'true'
    end

    it 'should convert endless exclusive range' do
      js = to_js('r = 1...')
      _(js).must_include 'new $Range(1, null, true)'
    end

    it 'should convert beginless inclusive range' do
      js = to_js('r = ..10')
      _(js).must_include 'new $Range(null, 10)'
      _(js).wont_include 'true'
    end

    it 'should convert beginless exclusive range' do
      js = to_js('r = ...10')
      _(js).must_include 'new $Range(null, 10, true)'
    end

    it 'should handle ranges with variables' do
      js = to_js('r = a..b')
      _(js).must_include 'new $Range(a, b)'
    end

    it 'should handle ranges with expressions' do
      js = to_js('r = (x + 1)..(y - 1)')
      _(js).must_include 'new $Range(x + 1, y - 1)'
    end
  end

  describe 'ranges in for loops' do
    it 'should use traditional for loop syntax for inclusive range' do
      js = to_js('for i in 1..10; puts i; end')
      _(js).must_include 'for (let i = 1; i <= 10; i++)'
      _(js).wont_include '$Range'
    end

    it 'should use traditional for loop syntax for exclusive range' do
      js = to_js('for i in 1...10; puts i; end')
      _(js).must_include 'for (let i = 1; i < 10; i++)'
      _(js).wont_include '$Range'
    end
  end

  describe 'ranges in case statements' do
    it 'should use comparison operators for inclusive range' do
      js = to_js('case x; when 1..10; puts "in range"; end')
      _(js).must_include 'x >= 1 && x <= 10'
      _(js).wont_include '$Range'
    end

    it 'should use comparison operators for exclusive range' do
      js = to_js('case x; when 1...10; puts "in range"; end')
      _(js).must_include 'x >= 1 && x < 10'
      _(js).wont_include '$Range'
    end
  end
end
