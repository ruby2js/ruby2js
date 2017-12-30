gem 'minitest'
require 'minitest/autorun'

describe "ES2015 support" do
  
  def to_js(string)
    Ruby2JS.convert(string, eslevel: :es2015).to_s
  end
  
  describe :templateLiteral do
    it "should convert interpolated strings into ES templates" do
      to_js( '"#{a}"' ).must_equal('`${a}`')
    end

    it "should escape stray ${} characters" do
      to_js( '"#{a}${a}"' ).must_equal("`${a}$\\{a}`")
    end

    it "should escape newlines in short strings" do
      to_js( "\"\#{a}\n\"" ).must_equal("`${a}\\n`")
    end

    it "should not escape newlines in long strings" do
      to_js( "\"\#{a}\n12345678901234567890123456789012345678901\"" ).
       must_equal("`${a}\n12345678901234567890123456789012345678901`")
    end
  end
end
