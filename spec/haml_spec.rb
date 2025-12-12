require 'minitest/autorun'
require 'ruby2js/filter/haml'

describe Ruby2JS::Filter::Haml do

  def to_js(string)
    _(Ruby2JS.convert(string, eslevel: 2022,
      filters: [Ruby2JS::Filter::Haml]).to_s)
  end

  describe "HAML buffer detection" do
    it "should detect _buf = ''.dup pattern" do
      # Simulating HAML 6+ compiled output
      code = <<~RUBY
        _buf = ''.dup
        _buf << "<h1>".freeze
        _buf << @title.to_s
        _buf << "</h1>".freeze
        _buf
      RUBY
      result = to_js(code)
      result.must_include 'function render('
      result.must_include 'let _buf = ""'
      result.must_include 'return _buf'
    end

    it "should detect _buf = ::String.new pattern" do
      code = <<~RUBY
        _buf = ::String.new
        _buf << "<p>".freeze
        _buf << @content.to_s
        _buf << "</p>".freeze
        _buf
      RUBY
      result = to_js(code)
      result.must_include 'function render('
      result.must_include 'let _buf = ""'
    end
  end

  describe "instance variable extraction" do
    it "should extract instance variables to destructured parameters" do
      code = <<~RUBY
        _buf = ''.dup
        _buf << @title.to_s
        _buf << @content.to_s
        _buf
      RUBY
      result = to_js(code)
      result.must_include '{ content, title }'
    end

    it "should handle templates with no instance variables" do
      code = <<~RUBY
        _buf = ''.dup
        _buf << "<p>Static</p>".freeze
        _buf
      RUBY
      result = to_js(code)
      # Should have empty params, not destructuring
      result.must_include 'function render()'
      result.wont_include 'function render({'
    end
  end

  describe "buffer operations" do
    it "should convert << to +=" do
      code = <<~RUBY
        _buf = ''.dup
        _buf << "<div>".freeze
        _buf
      RUBY
      result = to_js(code)
      result.must_include '_buf += "<div>"'
    end

    it "should strip .freeze calls" do
      code = <<~RUBY
        _buf = ''.dup
        _buf << "<span>".freeze
        _buf
      RUBY
      result = to_js(code)
      result.wont_include '.freeze'
      result.must_include '"<span>"'
    end

    it "should wrap non-strings in String()" do
      code = <<~RUBY
        _buf = ''.dup
        _buf << @count.to_s
        _buf
      RUBY
      result = to_js(code)
      result.must_include 'String(count)'
    end
  end

  describe "HAML escape handling" do
    it "should strip ::Haml::Util.escape_html wrapper" do
      code = <<~RUBY
        _buf = ''.dup
        _buf << (::Haml::Util.escape_html(@title)).to_s
        _buf
      RUBY
      result = to_js(code)
      result.must_include 'String(title)'
      result.wont_include 'escape_html'
      result.wont_include 'Haml'
    end
  end

  describe "final return" do
    it "should convert final _buf reference to return" do
      code = <<~RUBY
        _buf = ''.dup
        _buf << "<p>test</p>".freeze
        _buf
      RUBY
      result = to_js(code)
      result.must_include 'return _buf'
    end

    it "should strip .to_s on final buffer" do
      code = <<~RUBY
        _buf = ''.dup
        _buf << "<p>test</p>".freeze
        _buf.to_s
      RUBY
      result = to_js(code)
      result.must_include 'return _buf'
      result.wont_include '_buf.to_s'
    end
  end

  describe "non-HAML code" do
    it "should pass through non-HAML code unchanged" do
      result = to_js('x = 1 + 2')
      result.must_equal 'let x = 1 + 2'
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include Haml" do
      _(Ruby2JS::Filter::DEFAULTS).must_include Ruby2JS::Filter::Haml
    end
  end
end
