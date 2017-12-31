gem 'minitest'
require 'minitest/autorun'

describe "ES2015 support" do
  
  def to_js(string)
    Ruby2JS.convert(string, filters: [], eslevel: :es2015).to_s
  end
  
  describe :vars do
    it "should use let as the new var" do
      to_js( 'a = 1' ).must_equal('let a = 1')
    end

    it "should use const for constants" do
      to_js( 'A = 1' ).must_equal('const A = 1')
    end

    it "should handle scope" do
      to_js( 'b=0 if a==1' ).must_equal 'let b; if (a == 1) b = 0'
    end
  end

  describe :destructuring do
    it "should handle parallel assignment" do
      to_js( 'a,b=b,a' ).must_equal('let [a, b] = [b, a]')
    end
  end

  describe :objectLiteral do
    it "should handle computed property names" do
      to_js( '{a => 1}' ).must_equal('{[a]: 1}')
    end
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

  describe :operator do
    it "should parse exponential operators" do
      to_js( '2 ** 0.5' ).must_equal '2 ** 0.5'
    end
  end

  describe :fat_arrow do
    it "should handle simple lambda expressions" do
      to_js( 'foo = lambda {|x| x*x}' ).must_equal 'let foo = (x) => x * x'
    end

    it "should handle block parameters" do
      to_js( 'a {|b| c}' ).must_equal 'a((b) => c)'
    end

    it "should handle multi-statement blocks" do
      to_js( 'foo = proc {a;b}' ).must_equal 'let foo = () => {a; b}'
    end
  end
end
