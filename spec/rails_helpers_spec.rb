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
      result.must_include 'function render($context, { title })'
      result.must_include '_buf += "<h1>"'
      result.must_include 'String(title)'
    end

    it "should handle block expressions like form_for" do
      return skip() unless defined?(Ruby2JS::Erubi)
      result = erb_to_js('<%= form_for @user do |f| %><%= f.text_field :name %><% end %>')
      result.must_include 'function render($context, { user })'
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

    it "should include class attribute on form_with" do
      return skip() unless defined?(Ruby2JS::Erubi)
      result = erb_to_js('<%= form_with(model: @article, class: "contents") do |form| %><% end %>')
      result.must_include 'class="contents"'
      result.must_include '<form'
    end


    it "should include class attribute on text_field" do
      return skip() unless defined?(Ruby2JS::Erubi)
      result = erb_to_js('<%= form_with(model: @article) do |form| %><%= form.text_field :title, class: "input-lg" %><% end %>')
      result.must_include 'class="input-lg"'
      result.must_include 'type="text"'
    end

    it "should include class and rows on textarea" do
      return skip() unless defined?(Ruby2JS::Erubi)
      result = erb_to_js('<%= form_with(model: @article) do |form| %><%= form.textarea :body, rows: 4, class: "w-full" %><% end %>')
      result.must_include 'class="w-full"'
      result.must_include 'rows="4"'
      result.must_include '<textarea'
    end

    it "should include class on submit button" do
      return skip() unless defined?(Ruby2JS::Erubi)
      result = erb_to_js('<%= form_with(model: @article) do |form| %><%= form.submit class: "btn btn-primary" %><% end %>')
      # Static string output - quotes are escaped
      result.must_include 'class=\\"btn btn-primary\\"'
      result.must_include 'type=\\"submit\\"'
    end

    it "should include class on label" do
      return skip() unless defined?(Ruby2JS::Erubi)
      result = erb_to_js('<%= form_with(model: @article) do |form| %><%= form.label :title, class: "font-bold" %><% end %>')
      # Static string output - quotes are escaped
      result.must_include 'class=\\"font-bold\\"'
      result.must_include '<label'
    end

    it "should handle multiple field attributes" do
      return skip() unless defined?(Ruby2JS::Erubi)
      result = erb_to_js('<%= form_with(model: @user) do |f| %><%= f.text_field :name, placeholder: "Enter name", required: true, class: "form-control" %><% end %>')
      result.must_include 'class="form-control"'
      result.must_include 'placeholder="Enter name"'
      result.must_include 'required'
    end

    it "should include id attribute on text_field" do
      return skip() unless defined?(Ruby2JS::Erubi)
      result = erb_to_js('<%= form_with(model: @article) do |form| %><%= form.text_field :title, id: "article-title" %><% end %>')
      result.must_include 'id="article-title"'
    end

    it "should include style attribute on text_field" do
      return skip() unless defined?(Ruby2JS::Erubi)
      result = erb_to_js('<%= form_with(model: @article) do |form| %><%= form.text_field :title, style: "width: 100%" %><% end %>')
      result.must_include 'style="width: 100%"'
    end

    it "should handle conditional classes on form fields" do
      return skip() unless defined?(Ruby2JS::Erubi)
      result = erb_to_js('<%= form_with(model: @article) do |form| %><%= form.text_field :title, class: ["input", {"border-red": article.errors.any?}] %><% end %>')
      # Conditional classes generate runtime expressions
      result.must_include 'input'
      result.must_include 'border-red'
      result.must_include '?'
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
      # Conditional classes generate runtime expressions
      result.must_include 'rounded-md px-3'
      result.must_include 'errors ?'
      result.must_include 'text-red'
    end
  end

  describe 'button_to helper' do
    it "should include class attribute on button_to" do
      erb_src = '_erbout = +\'\'; _erbout.<<(( button_to("Delete", @article, method: :delete, class: "btn-danger text-white") ).to_s); _erbout'
      result = to_js(erb_src)
      # Template literal output - quotes not escaped
      result.must_include 'class="btn-danger text-white"'
      result.must_include '>Delete</button>'
    end

    it "should include form_class attribute on button_to" do
      erb_src = '_erbout = +\'\'; _erbout.<<(( button_to("Delete", @article, method: :delete, form_class: "inline-block", class: "btn") ).to_s); _erbout'
      result = to_js(erb_src)
      # Template literal output - quotes not escaped
      result.must_include '<form class="inline-block">'
      result.must_include 'class="btn"'
      result.wont_include 'style="display:inline"'
    end

    it "should handle button_to with turbo_confirm" do
      erb_src = '_erbout = +\'\'; _erbout.<<(( button_to("Delete", @article, method: :delete, data: { turbo_confirm: "Really?" }) ).to_s); _erbout'
      result = to_js(erb_src)
      result.must_include "confirm('Really?')"
    end

    it "should handle button_to with path helper" do
      erb_src = '_erbout = +\'\'; _erbout.<<(( button_to("Delete", article_path(@article), method: :delete, class: "btn-sm") ).to_s); _erbout'
      result = to_js(erb_src)
      # Template literal output - quotes not escaped
      result.must_include 'class="btn-sm"'
      result.must_include 'routes.article.delete'
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

    describe 'explicit target option' do
      def to_js_with_target(string, database:, target:)
        _(Ruby2JS.convert(string,
          filters: [Ruby2JS::Filter::Rails::Helpers, Ruby2JS::Filter::Erb, Ruby2JS::Filter::Functions],
          eslevel: 2015,
          database: database,
          target: target
        ).to_s)
      end

      it "should respect explicit target: 'browser' even with server database" do
        erb_src = '_buf = ::String.new; _buf << ( link_to("Articles", "/articles") ).to_s; _buf.to_s'
        result = to_js_with_target(erb_src, database: 'better_sqlite3', target: 'browser')
        result.must_include 'onclick='
        result.must_include 'navigate(event'
      end

      it "should respect explicit target: 'node' even with browser database" do
        erb_src = '_buf = ::String.new; _buf << ( link_to("Articles", "/articles") ).to_s; _buf.to_s'
        result = to_js_with_target(erb_src, database: 'dexie', target: 'node')
        result.must_include 'href='
        result.wont_include 'onclick='
      end

      it "should generate server-style form_tag with explicit target: 'node'" do
        erb_src = "_buf = ::String.new; _buf.append= form_tag articles_path do\n _buf << \"<button>Submit</button>\"; end\n_buf.to_s"
        result = to_js_with_target(erb_src, database: 'dexie', target: 'node')
        result.must_include 'action='
        result.must_include 'method="post"'
        result.wont_include 'onsubmit='
      end

      it "should generate server-style form_with with action and method for existing model" do
        erb_src = "_buf = ::String.new; _buf.append= form_with model: @article do |form|\n _buf << \"<button>Submit</button>\"; end\n_buf.to_s"
        result = to_js_with_target(erb_src, database: 'dexie', target: 'node')
        result.must_include 'action='
        result.must_include 'article_path'
        result.must_include 'articles_path'
        result.must_include 'method="post"'
        result.must_include '_method'
        result.must_include 'patch'
        result.wont_include 'onsubmit='
      end

      it "should use property access for model.id not function call" do
        erb_src = "_buf = ::String.new; _buf.append= form_with model: @article do |form|\n _buf << \"<button>Submit</button>\"; end\n_buf.to_s"
        result = to_js_with_target(erb_src, database: 'dexie', target: 'node')
        # article.id should be property access, not function call
        result.must_include 'article.id'
        result.wont_include 'article.id()'
      end

      it "should import path helpers for form_with model rather than passing as parameters" do
        erb_src = "_buf = ::String.new; _buf.append= form_with model: @article do |form|\n _buf << \"<button>Submit</button>\"; end\n_buf.to_s"
        result = to_js_with_target(erb_src, database: 'dexie', target: 'node')
        # Path helpers should be imported, not function parameters
        result.must_include 'import { article_path, articles_path } from'
        # The render function should only have article as parameter
        result.must_include 'function render($context, { article })'
        # Should NOT have path helpers as function parameters
        result.wont_include '{ article, article_path'
        result.wont_include '{ article, articles_path'
      end

      it "should generate server-style form_with with action for new model" do
        erb_src = "_buf = ::String.new; _buf.append= form_with model: Comment.new do |form|\n _buf << \"<button>Submit</button>\"; end\n_buf.to_s"
        result = to_js_with_target(erb_src, database: 'dexie', target: 'node')
        result.must_include 'action='
        result.must_include 'comments_path'
        result.must_include 'method="post"'
        result.wont_include '_method'
        result.wont_include 'onsubmit='
      end

      it "should generate nested resource form_with with parent model in path" do
        erb_src = "_buf = ::String.new; _buf.append= form_with model: [@article, Comment.new] do |form|\n _buf << \"<button>Submit</button>\"; end\n_buf.to_s"
        result = to_js_with_target(erb_src, database: 'dexie', target: 'node')
        result.must_include 'action='
        # Should pass parent model to path helper: comments_path(article)
        result.must_include 'comments_path(article)'
        result.must_include 'method="post"'
        result.wont_include 'comments_path()'
      end
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include Rails::Helpers" do
      _(Ruby2JS::Filter::DEFAULTS).must_include Ruby2JS::Filter::Rails::Helpers
    end
  end
end
