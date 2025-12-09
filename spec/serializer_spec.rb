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

  describe 'reindent' do
    it 'should indent content inside braces' do
      @serializer.puts '{'
      @serializer.puts 'content'
      @serializer.puts '}'
      @serializer.send(:reindent, @serializer.lines)
      _(@serializer.lines.map(&:indent)).must_equal [0, 2, 0, 0]
    end

    it 'should indent content inside brackets' do
      @serializer.puts '['
      @serializer.puts 'item'
      @serializer.puts ']'
      @serializer.send(:reindent, @serializer.lines)
      _(@serializer.lines.map(&:indent)).must_equal [0, 2, 0, 0]
    end

    it 'should indent content inside parentheses' do
      @serializer.puts '('
      @serializer.puts 'arg'
      @serializer.puts ')'
      @serializer.send(:reindent, @serializer.lines)
      _(@serializer.lines.map(&:indent)).must_equal [0, 2, 0, 0]
    end

    it 'should handle nested braces' do
      @serializer.puts 'if (true) {'
      @serializer.puts 'if (false) {'
      @serializer.puts 'inner'
      @serializer.puts '}'
      @serializer.puts '}'
      @serializer.send(:reindent, @serializer.lines)
      _(@serializer.lines.map(&:indent)).must_equal [0, 2, 4, 2, 0, 0]
    end

    it 'should handle closing brace at start of line' do
      @serializer.puts 'function() {'
      @serializer.puts 'body'
      @serializer.puts '}'
      @serializer.send(:reindent, @serializer.lines)
      _(@serializer.lines.map(&:indent)).must_equal [0, 2, 0, 0]
    end

    it 'should handle empty lines' do
      @serializer.puts '{'
      @serializer.puts ''
      @serializer.puts 'content'
      @serializer.puts '}'
      @serializer.send(:reindent, @serializer.lines)
      _(@serializer.lines.map(&:indent)).must_equal [0, 2, 2, 0, 0]
    end
  end

  describe 'respace' do
    it 'should remove truly empty lines' do
      # respace removes lines with length 0 (no tokens)
      # Note: puts '' creates a line with one empty token, length 0 means zero tokens
      @serializer.puts 'a'
      @serializer.puts 'b'
      @serializer.put 'c'
      @serializer.to_s
      _(@serializer.lines.length).must_equal 3
    end

    it 'should add blank line before indented block' do
      @serializer.puts 'x()'
      @serializer.puts 'if (true) {'
      @serializer.puts 'a()'
      @serializer.put '}'
      result = @serializer.to_s
      _(result).must_equal "x()\n\nif (true) {\n  a()\n}"
    end

    it 'should add blank line after indented block' do
      @serializer.puts 'if (true) {'
      @serializer.puts 'a()'
      @serializer.puts '}'
      @serializer.put 'x()'
      result = @serializer.to_s
      _(result).must_equal "if (true) {\n  a()\n}\n\nx()"
    end

    it 'should NOT add blank lines inside blocks' do
      @serializer.puts 'if (true) {'
      @serializer.puts 'a();'
      @serializer.puts 'b()'
      @serializer.put '}'
      result = @serializer.to_s
      _(result).must_equal "if (true) {\n  a();\n  b()\n}"
    end

    it 'should add single blank line between blocks' do
      @serializer.puts 'if (true) {'
      @serializer.puts 'a()'
      @serializer.puts '}'
      @serializer.puts 'if (false) {'
      @serializer.puts 'b()'
      @serializer.put '}'
      result = @serializer.to_s
      _(result).must_equal "if (true) {\n  a()\n}\n\nif (false) {\n  b()\n}"
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
