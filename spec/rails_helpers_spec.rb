require 'minitest/autorun'
require 'ruby2js/filter/erb'
require 'ruby2js/filter/rails/helpers'
require 'ruby2js/filter/functions'
require 'ruby2js/erubi'

describe Ruby2JS::Filter::Rails::Helpers do

  # Note: Rails::Helpers must come BEFORE Erb in filter list so its method
  # overrides (process_erb_block_append, etc.) take precedence
  def to_js(string, eslevel: 2015)
    _(Ruby2JS.convert(string, filters: [Ruby2JS::Filter::Rails::Helpers, Ruby2JS::Filter::Erb, Ruby2JS::Filter::Functions], eslevel: eslevel).to_s)
  end

  def erb_to_js(template, eslevel: 2015)
    src = Ruby2JS::Erubi.new(template).src
    _(Ruby2JS.convert(src, filters: [Ruby2JS::Filter::Rails::Helpers, Ruby2JS::Filter::Erb, Ruby2JS::Filter::Functions], eslevel: eslevel).to_s)
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
      # Template literals don't need escaped quotes
      result.must_include 'type="email"'
      result.must_include 'type="password"'
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

  describe 'link_to helper' do
    it "should convert static link_to to anchor with navigate" do
      erb_src = '_erbout = +\'\'; _erbout.<<(( link_to("Articles", "/articles") ).to_s); _erbout'
      result = to_js(erb_src)
      # Output is a JS string with escaped quotes
      result.must_include '<a href=\"/articles\"'
      result.must_include 'onclick=\"return navigate(event'
      result.must_include '>Articles</a>'
    end

    it "should convert link_to with path helper to anchor with navigate" do
      erb_src = '_erbout = +\'\'; _erbout.<<(( link_to("View", article_path(article)) ).to_s); _erbout'
      result = to_js(erb_src)
      # Template literal output - quotes not escaped
      result.must_include '<a href="'
      result.must_include 'article_path(article)'
      result.must_include 'navigate(event'
      result.must_include '>View</a>'
    end

    it "should handle link_to with dynamic text" do
      erb_src = '_erbout = +\'\'; _erbout.<<(( link_to(@article.title, article_path(@article)) ).to_s); _erbout'
      result = to_js(erb_src)
      # Template literal output - quotes not escaped
      result.must_include '<a href="'
      result.must_include '</a>'
    end

    it "should include class attribute on link_to" do
      erb_src = '_erbout = +\'\'; _erbout.<<(( link_to("Show", "/articles", class: "btn btn-primary") ).to_s); _erbout'
      result = to_js(erb_src)
      result.must_include 'class=\"btn btn-primary\"'
      result.must_include '>Show</a>'
    end

    it "should handle link_to with array class including conditionals" do
      # Tailwind pattern: class: ["base", {"conditional": condition}]
      erb_src = '_erbout = +\'\'; _erbout.<<(( link_to("Edit", "/edit", class: ["rounded-md", "px-3", {"text-red": errors}]) ).to_s); _erbout'
      result = to_js(erb_src)
      result.must_include 'class=\"rounded-md px-3 text-red\"'
    end
  end

  describe 'truncate helper' do
    it "should convert truncate with length option" do
      erb_src = '_erbout = +\'\'; _erbout.<<(( truncate(@body, length: 100) ).to_s); _erbout'
      result = to_js(erb_src)
      result.must_include 'truncate(body, {length: 100})'
    end

    it "should use default length when not specified" do
      erb_src = '_erbout = +\'\'; _erbout.<<(( truncate(@body) ).to_s); _erbout'
      result = to_js(erb_src)
      result.must_include 'truncate(body, {length: 30})'
    end
  end

  describe 'target detection' do
    def to_js_with_db(string, database:)
      _(Ruby2JS.convert(string,
        filters: [Ruby2JS::Filter::Rails::Helpers, Ruby2JS::Filter::Erb, Ruby2JS::Filter::Functions],
        eslevel: 2015,
        database: database
      ).to_s)
    end

    describe 'browser target (dexie)' do
      it "should generate onsubmit handler for form_tag" do
        # Format from ErbCompiler: _buf.append= form_tag ... do
        erb_src = "_buf = ::String.new; _buf.append= form_tag articles_path do\n _buf << \"<button>Submit</button>\"; end\n_buf.to_s"
        result = to_js_with_db(erb_src, database: 'dexie')
        result.must_include 'onsubmit='
        result.must_include 'routes.articles.post(event)'
        result.wont_include 'action='
      end

      it "should generate onclick handler for link_to" do
        erb_src = '_buf = ::String.new; _buf << ( link_to("Articles", "/articles") ).to_s; _buf.to_s'
        result = to_js_with_db(erb_src, database: 'dexie')
        result.must_include 'onclick='
        result.must_include 'navigate(event'
      end
    end

    describe 'server target (better_sqlite3)' do
      it "should generate action URL for form_tag" do
        erb_src = "_buf = ::String.new; _buf.append= form_tag articles_path do\n _buf << \"<button>Submit</button>\"; end\n_buf.to_s"
        result = to_js_with_db(erb_src, database: 'better_sqlite3')
        result.must_include 'action='
        result.must_include 'method="post"'
        result.wont_include 'onsubmit='
      end

      it "should generate plain href for link_to" do
        erb_src = '_buf = ::String.new; _buf << ( link_to("Articles", "/articles") ).to_s; _buf.to_s'
        result = to_js_with_db(erb_src, database: 'better_sqlite3')
        result.must_include 'href='
        result.wont_include 'onclick='
      end
    end

    describe 'default behavior' do
      it "should default to browser target when no database specified" do
        erb_src = '_buf = ::String.new; _buf << ( link_to("Articles", "/articles") ).to_s; _buf.to_s'
        result = to_js(erb_src)
        result.must_include 'onclick='
      end
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include Rails::Helpers" do
      _(Ruby2JS::Filter::DEFAULTS).must_include Ruby2JS::Filter::Rails::Helpers
    end
  end
end
