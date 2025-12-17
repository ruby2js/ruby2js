require 'minitest/autorun'
require 'ruby2js/filter/erb'
require 'ruby2js/filter/functions'
require 'ruby2js/erubi'

describe Ruby2JS::Filter::Erb do

  def to_js(string, eslevel: 2015)
    _(Ruby2JS.convert(string, filters: [Ruby2JS::Filter::Erb, Ruby2JS::Filter::Functions], eslevel: eslevel).to_s)
  end

  def erb_to_js(template, eslevel: 2015)
    src = Ruby2JS::Erubi.new(template).src
    _(Ruby2JS.convert(src, filters: [Ruby2JS::Filter::Erb, Ruby2JS::Filter::Functions], eslevel: eslevel).to_s)
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

  describe 'Ruby2JS::Erubi' do
    # Skip Erubi tests in selfhost - Erubi parser not yet implemented in JS
    it "should compile simple ERB templates" do
      return skip() unless defined?(Ruby2JS::Erubi)
      result = erb_to_js('<h1><%= @title %></h1>')
      result.must_include 'function render({ title })'
      result.must_include '_buf += "<h1>"'
      result.must_include 'String(title)'
    end

    it "should handle block expressions like form_for" do
      return skip() unless defined?(Ruby2JS::Erubi)
      result = erb_to_js('<%= form_for @user do |f| %><%= f.text_field :name %><% end %>')
      result.must_include 'function render({ user })'
      # The form_for block should generate HTML form tags (escaped in JS string)
      result.must_include 'data-model'
      result.must_include '</form>'
      # Form builder methods should generate HTML inputs
      result.must_include 'type='
      result.must_include 'user[name]'
    end

    it "should handle mixed static and dynamic content" do
      return skip() unless defined?(Ruby2JS::Erubi)
      result = erb_to_js('<div class="container"><%= @content %></div>')
      result.must_include 'container'
      result.must_include 'String(content)'
    end

    it "should handle form builder label method" do
      return skip() unless defined?(Ruby2JS::Erubi)
      result = erb_to_js('<%= form_for @user do |f| %><%= f.label :email %><% end %>')
      result.must_include 'user_email'
      result.must_include '>Email</label>'
    end

    it "should handle various input types" do
      return skip() unless defined?(Ruby2JS::Erubi)
      result = erb_to_js('<%= form_for @user do |f| %><%= f.email_field :email %><%= f.password_field :password %><% end %>')
      result.must_include 'type=\\"email\\"'
      result.must_include 'type=\\"password\\"'
    end

    it "should handle textarea" do
      return skip() unless defined?(Ruby2JS::Erubi)
      result = erb_to_js('<%= form_for @post do |f| %><%= f.text_area :body %><% end %>')
      result.must_include '<textarea'
      result.must_include 'post[body]'
    end

    it "should handle submit with custom label" do
      return skip() unless defined?(Ruby2JS::Erubi)
      result = erb_to_js('<%= form_for @user do |f| %><%= f.submit "Create Account" %><% end %>')
      result.must_include 'type=\\"submit\\"'
      result.must_include 'Create Account'
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include Erb" do
      _(Ruby2JS::Filter::DEFAULTS).must_include Ruby2JS::Filter::Erb
    end
  end
end
