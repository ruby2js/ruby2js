require 'minitest/autorun'
require 'ruby2js/filter/erb'
require 'ruby2js/filter/functions'
require 'ruby2js/erubi'

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
      to_js(erb_src).must_include '_erbout += `<h1>${title}</h1>`'
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

    it "should convert ivar assignments to local assignments" do
      # Test that @foo = value becomes foo = value (not this.#foo = value)
      erb_src = '_erbout = +\'\'; @scores = [1, 2, 3]; _erbout.<<(( @scores ).to_s); _erbout'
      result = to_js(erb_src)
      result.must_include 'scores = [1, 2, 3]'
      result.must_include 'String(scores)'
      result.wont_include '@scores'
      result.wont_include 'this.#scores'  # Not private field
    end
  end

  describe 'HERB output' do
    it "should convert simple HERB output to a render function" do
      # HERB output format: _buf = ::String.new; _buf << 'str'.freeze; _buf.to_s
      herb_src = "_buf = ::String.new; _buf << '<h1>'.freeze; _buf << (@title).to_s; _buf << '</h1>'.freeze; _buf.to_s"
      to_js(herb_src).must_include 'function render({ title })'
      to_js(herb_src).must_include 'let _buf = ""'
      to_js(herb_src).must_include '_buf += `<h1>${title}</h1>`'
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

  describe 'inline control flow' do
    it "should inline if/else as ternary in template literal" do
      erb_src = '_erbout = +\'\'; _erbout.<< "<div>".freeze; if show; _erbout.<< "<p>visible</p>".freeze; else; _erbout.<< "<p>hidden</p>".freeze; end; _erbout.<< "</div>".freeze; _erbout'
      result = to_js(erb_src)
      result.must_include '`<div>${show ? "<p>visible</p>" : "<p>hidden</p>"}</div>`'
    end

    it "should inline if-without-else with empty string fallback" do
      erb_src = '_erbout = +\'\'; _erbout.<< "<div>".freeze; if show; _erbout.<< "<p>visible</p>".freeze; end; _erbout.<< "</div>".freeze; _erbout'
      result = to_js(erb_src)
      result.must_include '`<div>${show ? "<p>visible</p>" : ""}</div>`'
    end

    it "should inline .each as .map().join in template literal" do
      erb_src = '_erbout = +\'\'; _erbout.<< "<ul>".freeze; for item in items; _erbout.<< "<li>".freeze; _erbout.<<(( item.name ).to_s); _erbout.<< "</li>".freeze; end; _erbout.<< "</ul>".freeze; _erbout'
      result = to_js(erb_src)
      result.must_include '`<ul>${items.map(item => (`<li>${item.name}</li>`)).join("")}</ul>`'
    end

    it "should not inline if with non-buf-only branches" do
      # Skip in selfhost — complex if with assignment doesn't parse
      return skip() unless defined?(Ruby2JS::Erubi)
      # if branch has an assignment — not buf_only
      erb_src = '_erbout = +\'\'; _erbout.<< "<div>".freeze; if show; x = 1; _erbout.<<(( x ).to_s); end; _erbout.<< "</div>".freeze; _erbout'
      result = to_js(erb_src)
      result.wont_include '? '
      result.must_include 'if (show)'
    end

    it "should recursively collapse buf appends within non-inlineable if" do
      # Skip in selfhost — standalone if block doesn't parse correctly
      return skip() unless defined?(Ruby2JS::Erubi)
      erb_src = '_erbout = +\'\'; if show; _erbout.<< "<p>".freeze; _erbout.<<(( @name ).to_s); _erbout.<< "</p>".freeze; end; _erbout'
      result = to_js(erb_src)
      result.must_include '`<p>${name}</p>`'
      result.must_include 'if (show)'
    end

    it "should inline if with expression values" do
      erb_src = '_erbout = +\'\'; _erbout.<< "<span>".freeze; if active; _erbout.<<(( @name ).to_s); else; _erbout.<< "anonymous".freeze; end; _erbout.<< "</span>".freeze; _erbout'
      result = to_js(erb_src)
      result.must_include '`<span>${active ? name : "anonymous"}</span>`'
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

    it "should transform yield to content reference" do
      erb_src = "def render\n_buf = ::String.new; _buf << (yield).to_s; _buf.to_s\nend"
      result = to_js_layout(erb_src)
      result.must_include 'content'
      result.wont_include 'yield'
    end

    it "should transform yield(:section) to contentFor lookup" do
      erb_src = "def render\n_buf = ::String.new; _buf << (yield(:head)).to_s; _buf.to_s\nend"
      result = to_js_layout(erb_src)
      result.must_include 'context.contentFor.head ?? ""'
      result.wont_include 'yield'
    end
  end

  describe 'def render wrapping' do
    it "should handle def render wrapping from ERB compiler" do
      erb_src = "def render\n_buf = ::String.new; _buf << \"<h1>\".freeze; _buf << (@title).to_s; _buf << \"</h1>\".freeze; _buf.to_s\nend"
      result = to_js(erb_src)
      result.must_include 'function render({ title })'
      result.must_include '_buf += `<h1>${title}</h1>`'
    end

    it "should handle def render with multiple ivars" do
      erb_src = "def render\n_buf = ::String.new; _buf << (@title).to_s; _buf << (@content).to_s; _buf.to_s\nend"
      result = to_js(erb_src)
      result.must_include '{ content, title }'
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include Erb" do
      _(Ruby2JS::Filter::DEFAULTS).must_include Ruby2JS::Filter::Erb
    end
  end
end
