gem 'minitest'
require 'minitest/autorun'

describe "ES2020 support" do
  
  def to_js( string)
    Ruby2JS.convert(string, eslevel: 2020, filters: []).to_s
  end
  
  describe :ClassFields do
    it "should convert private fields to #vars" do
      to_js( 'class C; def initialize; @a=1; end; def a; @a; end; end' ).
        must_equal 'class C {#a = 1; get a() {return this.#a}}'
    end
  end
end
