require 'minitest/autorun'
require 'ruby2js'

describe "template extraction" do

  def convert(string, options = {})
    Ruby2JS.convert(string, options)
  end

  describe "with template: option specified" do
    it "should extract template after __END__" do
      source = "x = 1\n__END__\n<div>hello</div>"
      result = convert(source, template: :vue)
      _(result.to_s).must_equal "let x = 1"
      _(result.template).must_equal "<div>hello</div>"
    end

    it "should handle multiline templates" do
      source = "x = 1\n__END__\n<article>\n  <h1>Title</h1>\n</article>"
      result = convert(source, template: :vue)
      _(result.to_s).must_equal "let x = 1"
      _(result.template).must_equal "<article>\n  <h1>Title</h1>\n</article>"
    end

    it "should preserve template whitespace" do
      source = "x = 1\n__END__\n  indented\n    more indented\n"
      result = convert(source, template: :vue)
      _(result.template).must_equal "  indented\n    more indented\n"
    end

    it "should handle empty template" do
      source = "x = 1\n__END__\n"
      result = convert(source, template: :vue)
      _(result.to_s).must_equal "let x = 1"
      _(result.template).must_equal ""
    end

    it "should handle __END__ without trailing newline" do
      source = "x = 1\n__END__"
      result = convert(source, template: :vue)
      _(result.to_s).must_equal "let x = 1"
      _(result.template).must_equal ""
    end

    it "should handle Windows line endings" do
      source = "x = 1\r\n__END__\r\n<div>hello</div>"
      result = convert(source, template: :vue)
      _(result.template).must_equal "<div>hello</div>"
    end

    it "should return nil when no __END__" do
      source = "x = 1"
      result = convert(source, template: :vue)
      _(result.to_s).must_equal "let x = 1"
      _(result.template).must_be_nil
    end
  end

  describe "without template: option" do
    it "should not set template even with __END__" do
      source = "x = 1\n__END__\n<div>hello</div>"
      result = convert(source)
      _(result.to_s).must_equal "let x = 1"
      _(result.template).must_be_nil
    end
  end

  describe "with AST node passed directly" do
    it "should return nil template" do
      source = "x = 1\n__END__\n<div>hello</div>"
      ast, _ = Ruby2JS.parse(source)
      result = convert(ast, template: :vue)
      _(result.template).must_be_nil
    end
  end

  describe "sourcemap generation" do
    it "should generate valid sourcemap for code portion only" do
      source = "x = 123\n__END__\n<div>hello</div>"
      result = convert(source, template: :vue, file: 'test.rb')
      sourcemap = result.sourcemap
      _(sourcemap[:version]).must_equal 3
      _(sourcemap[:mappings]).wont_be_empty
    end
  end

  describe "extract_template_from_source helper" do
    it "should extract content after __END__" do
      source = "code\n__END__\ntemplate"
      _(Ruby2JS.extract_template_from_source(source)).must_equal "template"
    end

    it "should return nil when no __END__" do
      source = "code"
      _(Ruby2JS.extract_template_from_source(source)).must_be_nil
    end

    it "should handle __END__ at start of line only" do
      source = "x = '__END__'\n__END__\ntemplate"
      _(Ruby2JS.extract_template_from_source(source)).must_equal "template"
    end
  end
end
