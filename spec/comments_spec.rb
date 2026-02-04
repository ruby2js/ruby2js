require 'minitest/autorun'
require 'ruby2js/filter/functions'

describe Ruby2JS::Filter::Functions do

  def to_js(string)
    _(Ruby2JS.convert(string, filters: [Ruby2JS::Filter::Functions]).to_s)
  end

  def to_js_no_filter(string)
    _(Ruby2JS.convert(string).to_s)
  end

  describe 'comments before code' do
    it "should handle comment before statement" do
      to_js("# comment\nstatement").must_include "// comment\nstatement()"
    end

    it "should handle comment before class" do
      js = to_js("# comment before class\nclass Greeter\nend")
      js.must_include "// comment before class"
      js.must_include "class Greeter"
    end

    it "should handle comment before method" do
      js = to_js("class Foo\n  # method comment\n  def bar\n    1\n  end\nend")
      js.must_include "// method comment"
      js.must_include "get bar()"
    end
  end

  describe 'comments between code' do
    it "should handle comment between statements" do
      js = to_js("x = 1\n# between\ny = 2")
      js.must_include "let x = 1"
      js.must_include "// between"
      js.must_include "let y = 2"
    end
  end

  describe 'trailing comments (same line)' do
    it "should handle trailing comment on last line" do
      to_js_no_filter("x = 1 # trailing").must_include "let x = 1 // trailing"
    end

    it "should handle trailing comment with more code after" do
      js = to_js_no_filter("x = 1 # trailing\ny = 2")
      js.must_include "let x = 1 // trailing"
      js.must_include "let y = 2"
      # Trailing comment should NOT appear before y = 2
      js.wont_include "// trailing\nlet y"
    end

    it "should handle trailing comment on statement in method" do
      js = to_js("class Foo\n  def bar\n    x = 1 # trailing\n  end\nend")
      js.must_include "let x = 1 // trailing"
    end
  end

  describe 'orphan comments (after all code)' do
    it "should preserve comment after all code" do
      js = to_js_no_filter("x = 1\n# after all code")
      js.must_include "let x = 1"
      js.must_include "// after all code"
    end

    it "should preserve multiple orphan comments" do
      js = to_js_no_filter("x = 1\n# first orphan\n# second orphan")
      js.must_include "// first orphan"
      js.must_include "// second orphan"
    end
  end

  describe 'block comments' do
    it "should handle =begin...=end" do
      js = to_js("=begin\ncomment\n=end\nstatement".gsub(/^\s+/, ''))
      js.must_equal "/*\ncomment\n*/\nstatement()"
    end

    it "should handle =begin...*/...=end with line comments" do
      js = to_js("=begin\n/* comment */\n=end\nstatement".gsub(/^\s+/, ''))
      js.must_equal "//\n///* comment */\n//\nstatement()"
    end
  end

  describe 'comment deduplication' do
    it "should not duplicate comments" do
      js = Ruby2JS.convert(<<-EOF, filters: [Ruby2JS::Filter::Functions]).to_s
        #statement
        statement

        #class
        class Class
        end
      EOF

      _(js.scan("//statement").length).must_equal 1
      _(js.scan("//class").length).must_equal 1
    end
  end

  describe 'comments with esm filter' do
    def to_js_esm(string)
      require 'ruby2js/filter/esm'
      _(Ruby2JS.convert(string, filters: [Ruby2JS::Filter::ESM, Ruby2JS::Filter::Functions]).to_s)
    end

    it "should preserve comment before export class" do
      js = to_js_esm("# comment before export\nexport class Exported\nend")
      js.must_include "// comment before export"
      js.must_include "export class Exported"
    end

    it "should preserve comment on class inside module" do
      require 'ruby2js/filter/esm'
      js = Ruby2JS.convert(<<-EOF, filters: [Ruby2JS::Filter::ESM, Ruby2JS::Filter::Functions]).to_s
        module MyModule
          # class comment
          class Greeter
            def greet
              "hello"
            end
          end
        end
      EOF

      _(js.scan("// class comment").length).must_equal 1
    end
  end

  describe 'pragma comments' do
    it "should not output pragma comments" do
      js = to_js_no_filter("x ||= 1 # Pragma: nullish")
      js.wont_include "Pragma"
      js.wont_include "nullish"
    end

    it "should not output pragma as trailing comment" do
      js = to_js_no_filter("x = 1 # Pragma: skip")
      js.wont_include "Pragma"
      js.wont_include "skip"
    end
  end
end
