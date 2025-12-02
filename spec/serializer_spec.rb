gem 'minitest'
require 'minitest/autorun'
require 'ruby2js'

class TestSerializer < Ruby2JS::Serializer
  attr_accessor :lines

  # Helper to convert lines to arrays for comparison
  def lines_as_arrays
    @lines.map(&:to_a)
  end
end

describe 'serializer tests' do
  before do
    @serializer = TestSerializer.new
    @serializer.enable_vertical_whitespace
  end

  describe 'put' do
    it 'should put a token' do
      @serializer.put 'hi'
      _(@serializer.lines_as_arrays).must_equal [['hi']]
    end

    it 'should put a token with a newline' do
      @serializer.put "hi\n"
      _(@serializer.lines_as_arrays).must_equal [['hi'], []]
    end

    it 'should handle multiple newlines' do
      @serializer.put "\nhi\n"
      _(@serializer.lines_as_arrays).must_equal [[''], ['hi'], []]
    end
  end

  describe 'puts' do
    it 'should puts a token' do
      @serializer.puts 'hi'
      _(@serializer.lines_as_arrays).must_equal [['hi'], []]
    end

    it 'should embedded multiple newlines' do
      @serializer.puts "\nhi"
      _(@serializer.lines_as_arrays).must_equal [[''], ['hi'], []]
    end
  end

  describe 'sput' do
    it 'should sput a token' do
      @serializer.sput 'hi'
      _(@serializer.lines_as_arrays).must_equal [[], ['hi']]
    end

    it 'should embedded multiple newlines' do
      @serializer.sput "hi\n"
      _(@serializer.lines_as_arrays).must_equal [[], ['hi'], []]
    end
  end

  describe 'output location' do
    it 'should track output location' do
      _(@serializer.output_location).must_equal [0,0]
      @serializer.put 'a'
      @serializer.put 'b'
      _(@serializer.output_location).must_equal [0,2]
      @serializer.puts 'c'
      @serializer.put 'd'
      @serializer.put 'e'
      _(@serializer.output_location).must_equal [1,2]
    end
  end

  describe 'capture' do
    it 'should capture tokens' do
      @serializer.put 'a'
      text = @serializer.capture do
        @serializer.put 'b'
        @serializer.puts 'c'
        @serializer.put 'd'
        @serializer.put 'e'
      end

      _(@serializer.lines_as_arrays).must_equal [['a']]
      _(text).must_equal "bc\nde"
    end
  end

  describe 'wrap' do
    it "shouldn't wrap short lines" do
      @serializer.put 'if (condition) '
      @serializer.wrap do
        @serializer.put 'statement'
      end
      _(@serializer.lines_as_arrays).must_equal [['if (condition) ', 'statement']]
    end

    it "should wrap long lines" do
      @serializer.put 'if (condition-condition-condition-condition-condition) '
      @serializer.wrap do
        @serializer.put 'statement-statement-statement-statement-statement'
      end
      _(@serializer.lines_as_arrays).must_equal [
        ["if (condition-condition-condition-condition-condition) ", "{"],
        ["statement-statement-statement-statement-statement"],
        ["}"]
      ]
    end
  end

  describe 'compact' do
    it "should compact short lines" do
      @serializer.compact do
        @serializer.puts '['
        @serializer.put 'token'
        @serializer.sput ']'
      end
      _(@serializer.lines_as_arrays).must_equal [["[", "token", "]"]]
    end

    it "shouldn't compact long lines" do
      @serializer.compact do
        @serializer.puts '['
        29.times { @serializer.put 'token, '}
        @serializer.put 'token'
        @serializer.sput ']'
      end
      _(@serializer.lines_as_arrays).must_equal [["["], ["token, "]*29 + ["token"], ["]"]]
    end

    it "shouldn't compact comments" do
      @serializer.compact do
        @serializer.puts '['
        @serializer.put '// comment'
        @serializer.sput ']'
      end
      _(@serializer.lines_as_arrays).must_equal [["["], ["// comment"], ["]"]]
    end
  end

  describe 'serialize' do
    it 'should serialize tokens' do
      @serializer.enable_vertical_whitespace

      @serializer.put 'a'
      @serializer.put 'b'
      @serializer.puts 'c'
      @serializer.put 'd'
      @serializer.put 'e'
      
      _(@serializer.to_s).must_equal "abc\nde"
    end
  end
end
