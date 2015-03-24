gem 'minitest'
require 'minitest/autorun'
require 'ruby2js'

class TestSerializer < Ruby2JS::Serializer
  attr_accessor :lines
end

describe 'serializer tests' do
  before do
    @serializer = TestSerializer.new
  end

  describe 'put' do
    it 'should put a token' do
      @serializer.put 'hi'
      @serializer.lines.must_equal [['hi']]
    end

    it 'should put a token with a newline' do
      @serializer.put "hi\n"
      @serializer.lines.must_equal [['hi'], []]
    end

    it 'should handle multiple newlines' do
      @serializer.put "\nhi\n"
      @serializer.lines.must_equal [[''], ['hi'], []]
    end
  end

  describe 'puts' do
    it 'should puts a token' do
      @serializer.puts 'hi'
      @serializer.lines.must_equal [['hi'], []]
    end

    it 'should embedded multiple newlines' do
      @serializer.puts "\nhi"
      @serializer.lines.must_equal [[''], ['hi'], []]
    end
  end

  describe 'sput' do
    it 'should sput a token' do
      @serializer.sput 'hi'
      @serializer.lines.must_equal [[], ['hi']]
    end

    it 'should embedded multiple newlines' do
      @serializer.sput "hi\n"
      @serializer.lines.must_equal [[], ['hi'], []]
    end
  end

  describe 'output location' do
    it 'should track output location' do
      @serializer.output_location.must_equal [0,0]
      @serializer.put 'a'
      @serializer.put 'b'
      @serializer.output_location.must_equal [0,2]
      @serializer.puts 'c'
      @serializer.put 'd'
      @serializer.put 'e'
      @serializer.output_location.must_equal [1,2]
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
      
      @serializer.lines.must_equal [['a']]
      text.must_equal "bc de"
    end
  end

  describe 'wrap' do
    it "shouldn't wrap short lines" do
      @serializer.put 'if (condition) '
      @serializer.wrap do
        @serializer.put 'statement'
      end
      @serializer.lines.must_equal [['if (condition) ', 'statement']]
    end

    it "should wrap long lines" do
      @serializer.put 'if (condition-condition-condition-condition-condition) '
      @serializer.wrap do
        @serializer.put 'statement-statement-statement-statement-statement'
      end
      @serializer.lines.must_equal [
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
      @serializer.lines.must_equal [["[", "token", "]"]]
    end

    it "shouldn't compact long lines" do
      @serializer.compact do
        @serializer.puts '['
        29.times { @serializer.put 'token, '}
        @serializer.put 'token'
        @serializer.sput ']'
      end
      @serializer.lines.must_equal [["["], ["token, "]*29 + ["token"], ["]"]]
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
      
      @serializer.serialize.must_equal "abc\nde"
    end
  end
end
