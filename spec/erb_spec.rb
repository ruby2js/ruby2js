require 'minitest/autorun'
require 'ruby2js/filter/erb'
require 'ruby2js/filter/functions'

describe Ruby2JS::Filter::Erb do

  def to_js(string, eslevel: 2015)
    _(Ruby2JS.convert(string, filters: [Ruby2JS::Filter::Erb, Ruby2JS::Filter::Functions], eslevel: eslevel).to_s)
  end

  describe 'ERB output' do
    it "should convert simple ERB output to a render function" do
      # ERB output format: _erbout = +''; _erbout.<< "str".freeze; _erbout
      erb_src = '_erbout = +\'\'; _erbout.<< "<h1>".freeze; _erbout.<<(( @title ).to_s); _erbout.<< "</h1>".freeze; _erbout'
      to_js(erb_src).must_include 'function render({ title })'
      to_js(erb_src).must_include 'let _erbout = ""'
      to_js(erb_src).must_include '_erbout += "<h1>"'
      to_js(erb_src).must_include 'String(title)'
      to_js(erb_src).must_include 'return _erbout'
    end

    it "should handle multiple instance variables" do
      erb_src = '_erbout = +\'\'; _erbout.<<(( @title ).to_s); _erbout.<<(( @content ).to_s); _erbout'
      result = to_js(erb_src)
      result.must_include '{ content, title }'
    end

    it "should convert ivars to local variables" do
      erb_src = '_erbout = +\'\'; _erbout.<<(( @name ).to_s); _erbout'
      result = to_js(erb_src)
      result.must_include 'String(name)'
      result.wont_include '@name'
      result.wont_include 'this.name'
    end
  end

  describe 'HERB output' do
    it "should convert simple HERB output to a render function" do
      # HERB output format: _buf = ::String.new; _buf << 'str'.freeze; _buf.to_s
      herb_src = "_buf = ::String.new; _buf << '<h1>'.freeze; _buf << (@title).to_s; _buf << '</h1>'.freeze; _buf.to_s"
      to_js(herb_src).must_include 'function render({ title })'
      to_js(herb_src).must_include 'let _buf = ""'
      to_js(herb_src).must_include '_buf += "<h1>"'
      to_js(herb_src).must_include 'String(title)'
    end

    it "should handle multiple instance variables in HERB" do
      herb_src = "_buf = ::String.new; _buf << (@title).to_s; _buf << (@content).to_s; _buf.to_s"
      result = to_js(herb_src)
      result.must_include '{ content, title }'
    end
  end

  describe 'loops' do
    it "should handle each loops with instance variables" do
      erb_src = '_erbout = +\'\'; @items.each do |item|; _erbout.<<(( item.name ).to_s); end; _erbout'
      result = to_js(erb_src)
      result.must_include 'function render({ items })'
      result.must_include 'for (let item of items)'
      result.must_include 'String(item.name)'
    end
  end

  describe 'edge cases' do
    it "should not transform non-ERB begin blocks" do
      # Regular Ruby code should pass through
      regular_ruby = 'x = 1; y = 2; x + y'
      result = to_js(regular_ruby)
      result.wont_include 'function render'
    end

    it "should handle empty templates" do
      erb_src = '_erbout = +\'\'; _erbout'
      result = to_js(erb_src)
      result.must_include 'function render()'
      result.must_include 'return _erbout'
    end
  end

  describe 'html_safe and raw' do
    it "should strip html_safe calls" do
      erb_src = '_erbout = +\'\'; _erbout.<<(( @content.html_safe ).to_s); _erbout'
      result = to_js(erb_src)
      result.must_include 'String(content)'
      result.wont_include 'html_safe'
      result.wont_include 'htmlSafe'
    end

    it "should strip raw() helper calls" do
      erb_src = '_erbout = +\'\'; _erbout.<<(( raw(@html) ).to_s); _erbout'
      result = to_js(erb_src)
      result.must_include 'String(html)'
      result.wont_include 'raw'
    end

    it "should handle raw with string literal" do
      erb_src = '_erbout = +\'\'; _erbout.<<(( raw("<b>bold</b>") ).to_s); _erbout'
      result = to_js(erb_src)
      result.must_include '<b>bold</b>'
      result.wont_include 'raw'
    end
  end

  describe 'layout mode' do
    def to_js_layout(string, eslevel: 2015)
      _(Ruby2JS.convert(string, filters: [Ruby2JS::Filter::Erb, Ruby2JS::Filter::Functions], eslevel: eslevel, layout: true).to_s)
    end

    it "should generate layout function with positional args" do
      erb_src = '_buf = ::String.new; _buf << "<html>".freeze; _buf << (@title).to_s; _buf << "</html>".freeze; _buf.to_s'
      result = to_js_layout(erb_src)
      result.must_include 'function layout(context, content)'
      result.wont_include 'function render'
    end

    it "should not use destructured kwargs in layout mode" do
      erb_src = '_buf = ::String.new; _buf << (@title).to_s; _buf.to_s'
      result = to_js_layout(erb_src)
      result.must_include 'function layout(context, content)'
      result.wont_include '$context'
      result.wont_include '{ title }'
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include Erb" do
      _(Ruby2JS::Filter::DEFAULTS).must_include Ruby2JS::Filter::Erb
    end
  end
end
