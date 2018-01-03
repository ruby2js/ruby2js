gem 'minitest'
require 'minitest/autorun'

describe 'Ruby2JS::ExecJS' do
  before do
    begin
      require 'ruby2js/execjs'
      @skip = false
    rescue LoadError
      @skip = true
    end
  end

  it "should handle compile" do
    skip if @skip
    Ruby2JS.compile('i=1').eval('i+1').must_equal 2
  end

  it "should handle eval" do
    skip if @skip
    Ruby2JS.eval('"abc" =~ /b/', filters: []).must_equal true
  end

  it "should handle exec" do
    skip if @skip
    Ruby2JS.exec('x=%w(a b); x << "c"; return x.pop()').must_equal 'c'
  end
end
