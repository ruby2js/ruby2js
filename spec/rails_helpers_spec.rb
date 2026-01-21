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
      result.must_include 'function render({ $context, title })'
      result.must_include '_buf += "<h1>"'
      result.must_include 'String(title)'
    end

    it "should handle block expressions like form_for" do
      return skip() unless defined?(Ruby2JS::Erubi)
      result = erb_to_js('<%= form_for @user do |f| %><%= f.text_field :name %><% end %>')
      result.must_include 'function render({ $context, user })'
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

    it "should handle form_with url: with static string" do
      return skip() unless defined?(Ruby2JS::Erubi)
      result = erb_to_js('<%= form_with(url: "/photos", method: :post, class: "my-form") do |f| %><%= f.text_field :caption %><% end %>')
      result.must_include 'action=\\"/photos\\"'
      result.must_include 'method=\\"post\\"'
      result.must_include 'class=\\"my-form\\"'
      result.must_include '<form'
    end

    it "should handle form_with url: with path helper" do
      return skip() unless defined?(Ruby2JS::Erubi)
      result = erb_to_js('<%= form_with(url: photos_path, method: :post) do |f| %><%= f.text_field :caption %><% end %>')
      result.must_include 'action="'
      result.must_include 'photos_path'
      result.must_include 'method="post"'
      # Path helper should be imported
      result.must_include 'import { photos_path }'
    end

    it "should handle form_with url: with data attributes" do
      return skip() unless defined?(Ruby2JS::Erubi)
      result = erb_to_js('<%= form_with(url: "/photos", method: :post, data: { turbo_frame: "modal" }) do |f| %><% end %>')
      result.must_include 'action=\\"/photos\\"'
      result.must_include 'data-turbo-frame=\\"modal\\"'
    end

    it "should handle form_with url: with method override (patch)" do
      return skip() unless defined?(Ruby2JS::Erubi)
      result = erb_to_js('<%= form_with(url: "/photos/1", method: :patch) do |f| %><% end %>')
      result.must_include 'action=\\"/photos/1\\"'
      result.must_include 'method=\\"post\\"'
      result.must_include '_method'
      result.must_include 'patch'
    end

    it "should handle form_with url: with method override (delete)" do
      return skip() unless defined?(Ruby2JS::Erubi)
      result = erb_to_js('<%= form_with(url: "/photos/1", method: :delete) do |f| %><% end %>')
      result.must_include 'action=\\"/photos/1\\"'
      result.must_include 'method=\\"post\\"'
      result.must_include '_method'
      result.must_include 'delete'
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

    it "should include data attributes on text_field" do
      return skip() unless defined?(Ruby2JS::Erubi)
      result = erb_to_js('<%= form_with(model: @message) do |form| %><%= form.text_field :body, data: { chat_target: "body" } %><% end %>')
      result.must_include 'data-chat-target="body"'
    end

    it "should convert underscores to dashes in data attribute names" do
      return skip() unless defined?(Ruby2JS::Erubi)
      result = erb_to_js('<%= form_with(model: @user) do |form| %><%= form.text_field :name, data: { controller_name: "user", action_type: "submit" } %><% end %>')
      result.must_include 'data-controller-name="user"'
      result.must_include 'data-action-type="submit"'
    end

    it "should handle data attributes with boolean values" do
      return skip() unless defined?(Ruby2JS::Erubi)
      result = erb_to_js('<%= form_with(model: @user) do |form| %><%= form.text_field :name, data: { turbo: true, disabled: false } %><% end %>')
      result.must_include 'data-turbo="true"'
      result.must_include 'data-disabled="false"'
    end

    it "should handle data attributes alongside other options" do
      return skip() unless defined?(Ruby2JS::Erubi)
      result = erb_to_js('<%= form_with(model: @user) do |form| %><%= form.text_field :name, class: "input", placeholder: "Name", data: { target: "form.input" } %><% end %>')
      result.must_include 'class="input"'
      result.must_include 'placeholder="Name"'
      result.must_include 'data-target="form.input"'
    end

    it "should include data attributes on form_with tag" do
      return skip() unless defined?(Ruby2JS::Erubi)
      result = erb_to_js('<%= form_with(model: @message, class: "space-y-4", data: { action: "turbo:submit-end->chat#clearInput" }) do |form| %><% end %>')
      result.must_include 'data-action="turbo:submit-end->chat#clearInput"'
      result.must_include 'class="space-y-4"'
    end

    it "should handle multiple data attributes on form_with tag" do
      return skip() unless defined?(Ruby2JS::Erubi)
      result = erb_to_js('<%= form_with(model: @article, data: { controller: "form", turbo_frame: "modal" }) do |form| %><% end %>')
      result.must_include 'data-controller="form"'
      result.must_include 'data-turbo-frame="modal"'
    end
  end

  describe 'link_to helper' do
    it "should convert static link_to to anchor (Turbo handles navigation)" do
      erb_src = '_erbout = +\'\'; _erbout.<<(( link_to("Articles", "/articles") ).to_s); _erbout'
      result = to_js(erb_src)
      # Output is a JS string with escaped quotes
      result.must_include '<a href=\"/articles\"'
      result.wont_include 'onclick='  # Turbo handles navigation, no onclick needed
      result.must_include '>Articles</a>'
    end

    it "should convert link_to with path helper to anchor (Turbo handles navigation)" do
      erb_src = '_erbout = +\'\'; _erbout.<<(( link_to("View", article_path(article)) ).to_s); _erbout'
      result = to_js(erb_src)
      # Template literal output - quotes not escaped
      result.must_include '<a href="'
      result.must_include 'article_path(article)'
      result.wont_include 'onclick='  # Turbo handles navigation, no onclick needed
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

    it "should convert link_to with bare method call (partial local) to path helper" do
      # In ERB partials, local variables like 'article' are parsed as bare method calls (:send with nil receiver)
      # link_to("Show", article) should generate article_path(article), not article()
      erb_src = '_erbout = +\'\'; _erbout.<<(( link_to("Show", article) ).to_s); _erbout'
      result = to_js(erb_src)
      result.must_include 'article_path(article)'
      result.wont_include 'article()'
      result.must_include '>Show</a>'
    end

    it "should not double _path suffix when path helper is already specified" do
      # link_to("Back", articles_path) should generate articles_path(), not articles_path_path()
      erb_src = '_erbout = +\'\'; _erbout.<<(( link_to("Back", articles_path) ).to_s); _erbout'
      result = to_js(erb_src)
      result.must_include 'articles_path()'
      result.wont_include 'articles_path_path'
      result.must_include '>Back</a>'
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
      result.must_include 'class="inline-block"'  # form_class on the form element
      result.must_include 'class="btn"'  # class on the button element
      result.wont_include 'style="display:inline"'
    end

    it "should handle button_to with turbo_confirm (uses data attribute)" do
      erb_src = '_erbout = +\'\'; _erbout.<<(( button_to("Delete", @article, method: :delete, data: { turbo_confirm: "Really?" }) ).to_s); _erbout'
      result = to_js(erb_src)
      # Turbo handles confirmation via data attribute, not onclick confirm()
      result.must_include 'data-turbo-confirm="Really?"'
      result.wont_include "confirm("
    end

    it "should handle button_to with path helper (uses Turbo form)" do
      erb_src = '_erbout = +\'\'; _erbout.<<(( button_to("Delete", article_path(@article), method: :delete, class: "btn-sm") ).to_s); _erbout'
      result = to_js(erb_src)
      # Template literal output - quotes not escaped
      result.must_include 'class="btn-sm"'
      # Now uses Turbo-compatible forms instead of onclick routes
      result.must_include 'method="post"'
      result.must_include '_method" value="delete"'
      result.must_include 'article_path(article)'
    end

    it "should convert button_to with bare method call (partial local) to path helper" do
      # In ERB partials, local variables like 'article' are parsed as bare method calls (:send with nil receiver)
      # button_to("Delete", article, method: :delete) should use article_path(article), not article()
      erb_src = '_erbout = +\'\'; _erbout.<<(( button_to("Delete", article, method: :delete) ).to_s); _erbout'
      result = to_js(erb_src)
      result.must_include 'article_path(article)'
      result.wont_include 'article()'
      result.must_include '>Delete</button>'
    end

    it "should handle button_to with nested resource array path" do
      # button_to("Delete", [comment.article, comment], method: :delete)
      # Should generate comment_path(comment.article, comment)
      erb_src = '_erbout = +\'\'; _erbout.<<(( button_to("Delete", [comment.article, comment], method: :delete) ).to_s); _erbout'
      result = to_js(erb_src)
      result.must_include 'comment_path('
      result.must_include 'comment.article'
      result.wont_include '{ _path }'  # Should not import generic _path
      result.must_include '>Delete</button>'
    end
  end

  describe 'render helper' do
    it "should handle render with method call collection (async)" do
      # render @article.comments -> (await article.comments).map(comment => _comment_module.render(...)).join('')
      # Association access returns a Promise, so needs async render function and await
      erb_src = '_erbout = +\'\'; _erbout.<<(( render(@article.comments) ).to_s); _erbout'
      result = to_js(erb_src)
      # Should import from the model's view directory
      result.must_include 'import * as _comment_module from "../comments/_comment.js"'
      # Should be an async function
      result.must_include 'async function render'
      # Should await the association access
      result.must_include '(await article.comments).map'
      result.must_include '_comment_module.render'
    end

    it "should handle render with ivar collection (sync)" do
      # render @messages -> messages.map(message => _message_module.render(...)).join('')
      # Instance variables passed directly are already resolved, no await needed
      erb_src = '_erbout = +\'\'; _erbout.<<(( render(@messages) ).to_s); _erbout'
      result = to_js(erb_src)
      # Should import from current directory (same as singular model name)
      result.must_include 'import * as _message_module from "./_message.js"'
      # Should NOT be async (no association access)
      result.must_include 'function render'
      result.wont_include 'async function render'
      # Should map over the collection without await
      result.must_include 'messages.map'
      result.wont_include 'await messages'
      result.must_include '_message_module.render'
    end

    it "should handle association.size with async" do
      # article.comments.size -> (await article.comments).size
      # Association access returns a Promise, so needs async render function and await
      erb_src = '_erbout = +\'\'; _erbout.<<(( article.comments.size ).to_s); _erbout'
      result = to_js(erb_src)
      # Should be an async function
      result.must_include 'async function render'
      # Should await the association and access .size as property (no parens)
      result.must_include '(await article.comments).size'
      result.wont_include '.size()'  # Should be property access, not method call
    end

    it "should handle association.count with async" do
      # article.comments.count -> (await article.comments).count
      erb_src = '_erbout = +\'\'; _erbout.<<(( article.comments.count ).to_s); _erbout'
      result = to_js(erb_src)
      result.must_include 'async function render'
      result.must_include '(await article.comments).count'
    end

    it "should handle association.length with async" do
      # article.comments.length -> (await article.comments).length
      erb_src = '_erbout = +\'\'; _erbout.<<(( article.comments.length ).to_s); _erbout'
      result = to_js(erb_src)
      result.must_include 'async function render'
      result.must_include '(await article.comments).length'
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

    # With Turbo integration, both browser and server targets generate the same HTML
    # (standard forms and links without onclick/onsubmit handlers).
    # Turbo intercepts navigation and form submissions automatically.

    describe 'browser target (dexie)' do
      it "should generate standard form_tag (Turbo handles submission)" do
        # Format from ErbCompiler: _buf.append= form_tag ... do
        erb_src = "_buf = ::String.new; _buf.append= form_tag articles_path do\n _buf << \"<button>Submit</button>\"; end\n_buf.to_s"
        result = to_js_with_db(erb_src, database: 'dexie')
        result.must_include 'action='
        result.must_include 'method="post"'
        result.wont_include 'onsubmit='  # Turbo handles submission
      end

      it "should generate standard link_to (Turbo handles navigation)" do
        erb_src = '_buf = ::String.new; _buf << ( link_to("Articles", "/articles") ).to_s; _buf.to_s'
        result = to_js_with_db(erb_src, database: 'dexie')
        result.must_include 'href='
        result.wont_include 'onclick='  # Turbo handles navigation
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
      it "should generate standard links (Turbo handles navigation)" do
        erb_src = '_buf = ::String.new; _buf << ( link_to("Articles", "/articles") ).to_s; _buf.to_s'
        result = to_js(erb_src)
        result.must_include 'href='
        result.wont_include 'onclick='  # Turbo handles navigation
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

      it "should generate standard link (Turbo handles navigation regardless of target)" do
        erb_src = '_buf = ::String.new; _buf << ( link_to("Articles", "/articles") ).to_s; _buf.to_s'
        result = to_js_with_target(erb_src, database: 'better_sqlite3', target: 'browser')
        result.must_include 'href='
        result.wont_include 'onclick='  # Turbo handles navigation
      end

      it "should generate standard link for node target" do
        erb_src = '_buf = ::String.new; _buf << ( link_to("Articles", "/articles") ).to_s; _buf.to_s'
        result = to_js_with_target(erb_src, database: 'dexie', target: 'node')
        result.must_include 'href='
        result.wont_include 'onclick='
      end

      it "should generate standard form_tag for node target" do
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
        result.must_include 'function render({ $context, article })'
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

      it "should generate standard nested resource form_with (Turbo handles submission)" do
        erb_src = "_buf = ::String.new; _buf.append= form_with model: [@article, Comment.new] do |form|\n _buf << \"<button>Submit</button>\"; end\n_buf.to_s"
        result = to_js_with_target(erb_src, database: 'dexie', target: 'browser')
        # Should generate standard form with action
        result.must_include 'action='
        result.must_include 'comments_path(article)'
        result.must_include 'method="post"'
        result.wont_include 'onsubmit='  # Turbo handles submission
      end

      it "should generate standard nested resource button_to delete (Turbo handles submission)" do
        erb_src = '_buf = ::String.new; _buf << ( button_to "Delete", [@article, comment], method: :delete ).to_s; _buf.to_s'
        result = to_js_with_target(erb_src, database: 'dexie', target: 'browser')
        # Should generate Turbo-compatible form with data attributes
        result.must_include 'method="post"'
        result.must_include '_method" value="delete"'
        result.must_include 'data-turbo-confirm='
        result.wont_include 'onclick='  # Turbo handles submission
      end

      it "should use TurboBroadcast.subscribe for browser target with turbo_stream_from" do
        erb_src = '_buf = ::String.new; _buf << ( turbo_stream_from "chat_room" ).to_s; _buf.to_s'
        result = to_js_with_target(erb_src, database: 'dexie', target: 'browser')
        result.must_include 'TurboBroadcast.subscribe("chat_room")'
        result.wont_include '<script'
      end

      it "should use turbo_stream_from helper for server target" do
        erb_src = '_buf = ::String.new; _buf << ( turbo_stream_from "chat_room" ).to_s; _buf.to_s'
        result = to_js_with_target(erb_src, database: 'sqlite3', target: 'node')
        # Server targets use turbo_stream_from helper which renders <turbo-cable-stream-source>
        result.must_include 'turbo_stream_from'
        result.must_include 'import'
        result.must_include 'chat_room'
        result.wont_include 'TurboBroadcast.subscribe'
      end

      it "should handle dynamic channel names for server target with turbo_stream_from" do
        erb_src = '_buf = ::String.new; _buf << ( turbo_stream_from "room_#{room_id}" ).to_s; _buf.to_s'
        result = to_js_with_target(erb_src, database: 'sqlite3', target: 'node')
        # Dynamic channel uses template literal
        result.must_include 'turbo_stream_from'
        result.must_include 'room_'
        result.must_include '${room_id}'
      end

      it "should use turbo_stream_from helper for Cloudflare target" do
        erb_src = '_buf = ::String.new; _buf << ( turbo_stream_from "notifications" ).to_s; _buf.to_s'
        result = to_js_with_target(erb_src, database: 'd1', target: 'cloudflare')
        # Cloudflare target also uses turbo_stream_from helper
        result.must_include 'turbo_stream_from'
        result.must_include 'notifications'
      end
    end
  end

  describe 'csrf_meta_tags helper' do
    it "should return the CSRF meta tag from context" do
      erb_src = '_erbout = +\'\'; _erbout.<<(( csrf_meta_tags ).to_s); _erbout'
      result = to_js(erb_src)
      # csrf_meta_tags returns the global $csrfMetaTag or empty string
      result.must_include '$csrfMetaTag'
      result.must_include '?? ""'  # Uses nullish coalescing
    end
  end

  describe 'authenticity_token in forms' do
    it "should include authenticity_token hidden field in button_to delete form" do
      erb_src = '_erbout = +\'\'; _erbout.<<(( button_to("Delete", @article, method: :delete) ).to_s); _erbout'
      result = to_js(erb_src)
      result.must_include 'name="authenticity_token"'
      result.must_include '$context.authenticityToken'
    end

    it "should include authenticity_token hidden field in form_for" do
      return skip() unless defined?(Ruby2JS::Erubi)
      result = erb_to_js('<%= form_for @user do |f| %><%= f.submit %><% end %>')
      result.must_include 'name="authenticity_token"'
      result.must_include '$context.authenticityToken'
    end

    it "should include authenticity_token hidden field in form_with" do
      return skip() unless defined?(Ruby2JS::Erubi)
      result = erb_to_js('<%= form_with(model: @article) do |form| %><%= form.submit %><% end %>')
      result.must_include 'name="authenticity_token"'
      result.must_include '$context.authenticityToken'
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include Rails::Helpers" do
      _(Ruby2JS::Filter::DEFAULTS).must_include Ruby2JS::Filter::Rails::Helpers
    end
  end
end
