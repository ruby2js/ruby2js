gem 'minitest'
require 'minitest/autorun'

describe "sourcemap" do

  def to_js(string)
    _(Ruby2JS.convert(string).sourcemap)
  end

  it "should return the sourcemap data" do
    to_js("x = 123; puts x").
      must_equal({:version=>3, :file=>"", :sources=>[""], :mappings=>"QAAI,GAAJ,SAAS,KAAK,CAAL"})
  end

end
