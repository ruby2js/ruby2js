require 'minitest/autorun'
require 'ruby2js/filter/rails/controller'
require 'ruby2js/filter/functions'

describe Ruby2JS::Filter::Rails::Controller do
  def to_js(source)
    Ruby2JS.convert(source, filters: [
      Ruby2JS::Filter::Rails::Controller,
      Ruby2JS::Filter::Functions
    ]).to_s
  end

  describe 'class detection' do
    it "transforms controller class to export module" do
      source = <<~RUBY
        class ArticlesController < ApplicationController
          def index
            @articles = Article.all
          end
        end
      RUBY

      result = to_js(source)
      _(result).must_include 'export'
      _(result).must_include 'ArticlesController'
      _(result).must_include 'function index(context)'
    end

    it "ignores non-controller classes" do
      source = <<~RUBY
        class Article < ApplicationRecord
          def save
            true
          end
        end
      RUBY

      result = to_js(source)
      _(result).must_include 'class Article'
      _(result).wont_include 'export(const'
    end
  end

  describe 'method transformation' do
    it "converts instance methods to module functions" do
      source = <<~RUBY
        class ArticlesController < ApplicationController
          def show
            @article = Article.find(params[:id])
          end
        end
      RUBY

      result = to_js(source)
      _(result).must_include 'async function show(context, id)'
      _(result).must_include 'let article = await Article.find(id)'
    end

    it "renames new action to $new (reserved word)" do
      source = <<~RUBY
        class ArticlesController < ApplicationController
          def new
            @article = Article.new
          end
        end
      RUBY

      result = to_js(source)
      _(result).must_include 'function $new(context)'
    end

    it "adds id parameter for show, edit, destroy; id and params for update" do
      source = <<~RUBY
        class ArticlesController < ApplicationController
          def show; end
          def edit; end
          def update; end
          def destroy; end
        end
      RUBY

      result = to_js(source)
      _(result).must_include 'function show(context, id)'
      _(result).must_include 'function edit(context, id)'
      _(result).must_include 'function update(context, id, params)'
      _(result).must_include 'function destroy(context, id)'
    end
  end

  describe 'instance variable transformation' do
    it "converts @ivar assignments to local variables" do
      source = <<~RUBY
        class ArticlesController < ApplicationController
          def index
            @articles = Article.all
          end
        end
      RUBY

      result = to_js(source)
      _(result).must_include 'let articles = await Article.all()'
      _(result).wont_include '@articles'
    end

    it "passes ivars to view calls" do
      source = <<~RUBY
        class ArticlesController < ApplicationController
          def index
            @articles = Article.all
          end
        end
      RUBY

      result = to_js(source)
      _(result).must_include 'ArticleViews.index({$context: context, articles})'
    end
  end

  describe 'params transformation' do
    it "converts params[:id] to id parameter" do
      source = <<~RUBY
        class ArticlesController < ApplicationController
          def show
            @article = Article.find(params[:id])
          end
        end
      RUBY

      result = to_js(source)
      _(result).must_include 'Article.find(id)'
      _(result).wont_include 'params['
    end

    it "adds params parameter to create action" do
      source = <<~RUBY
        class ArticlesController < ApplicationController
          def create
            @article = Article.new(article_params)
          end

          private
          def article_params
            params.require(:article).permit(:title, :body)
          end
        end
      RUBY

      result = to_js(source)
      _(result).must_include 'function create(context, params)'
      _(result).must_include 'new Article(params)'
      _(result).wont_include 'article_params'
      _(result).wont_include 'require'
      _(result).wont_include 'permit'
    end

    it "adds id and params parameters to update action" do
      source = <<~RUBY
        class ArticlesController < ApplicationController
          def update
            @article = Article.find(params[:id])
            @article.update(article_params)
          end

          private
          def article_params
            params.require(:article).permit(:title, :body)
          end
        end
      RUBY

      result = to_js(source)
      _(result).must_include 'function update(context, id, params)'
      _(result).must_include 'Article.find(id)'
      _(result).must_include 'article.update(params)'
    end
  end

  describe 'redirect_to transformation' do
    it "converts redirect_to path helper to hash" do
      source = <<~RUBY
        class ArticlesController < ApplicationController
          def destroy
            redirect_to articles_path
          end
        end
      RUBY

      result = to_js(source)
      _(result).must_include '{redirect: "/articles"}'
    end

    it "converts redirect_to @model to dynamic path" do
      source = <<~RUBY
        class ArticlesController < ApplicationController
          def create
            @article = Article.new
            redirect_to @article
          end
        end
      RUBY

      result = to_js(source)
      _(result).must_include '{redirect: `/articles/${article.id'
    end
  end

  describe 'render transformation' do
    it "converts render :action to hash" do
      source = <<~RUBY
        class ArticlesController < ApplicationController
          def create
            render :new
          end
        end
      RUBY

      result = to_js(source)
      _(result).must_include '{render:'
    end
  end

  describe 'before_action' do
    it "inlines before_action code into actions" do
      source = <<~RUBY
        class ArticlesController < ApplicationController
          before_action :set_article, only: [:show]

          def show
          end

          private

          def set_article
            @article = Article.find(params[:id])
          end
        end
      RUBY

      result = to_js(source)
      _(result).must_include 'async function show(context, id)'
      _(result).must_include 'let article = await Article.find(id)'
    end

    it "respects only: constraint" do
      source = <<~RUBY
        class ArticlesController < ApplicationController
          before_action :set_article, only: [:show]

          def index
            @articles = Article.all
          end

          def show
          end

          private

          def set_article
            @article = Article.find(params[:id])
          end
        end
      RUBY

      result = to_js(source)
      # index should NOT have set_article code
      _(result).must_match(/async function index\(context\).*?let articles = await Article\.all\(\)/m)
      # show SHOULD have set_article code
      _(result).must_match(/async function show\(context, id\).*?let article = await Article\.find\(id\)/m)
    end

    it "collects ivars from before_action methods" do
      source = <<~RUBY
        class ArticlesController < ApplicationController
          before_action :set_article, only: [:show]

          def show
          end

          private

          def set_article
            @article = Article.find(params[:id])
          end
        end
      RUBY

      result = to_js(source)
      # The article ivar from set_article should be passed to view
      _(result).must_include 'ArticleViews.show({$context: context, article})'
    end
  end

  describe 'view module naming' do
    it "uses singular form for view module" do
      source = <<~RUBY
        class ArticlesController < ApplicationController
          def index
            @articles = Article.all
          end
        end
      RUBY

      result = to_js(source)
      _(result).must_include 'ArticleViews'
      _(result).wont_include 'ArticlesViews'
    end
  end

  describe 'return values' do
    it "adds return to view calls" do
      source = <<~RUBY
        class ArticlesController < ApplicationController
          def index
            @articles = Article.all
          end
        end
      RUBY

      result = to_js(source)
      _(result).must_include 'return ArticleViews.index'
    end

    it "adds return to redirect hashes" do
      source = <<~RUBY
        class ArticlesController < ApplicationController
          def destroy
            redirect_to articles_path
          end
        end
      RUBY

      result = to_js(source)
      _(result).must_include 'return {redirect:'
    end
  end

  describe 'respond_to with turbo_stream' do
    it "generates Accept header check when both html and turbo_stream present" do
      source = <<~RUBY
        class ArticlesController < ApplicationController
          def create
            @article = Article.new(params)
            if @article.save
              respond_to do |format|
                format.html { redirect_to @article }
                format.turbo_stream { turbo_stream.append "articles", @article }
              end
            end
          end
        end
      RUBY

      result = to_js(source)
      # Should check Accept header
      _(result).must_include 'context.request.headers.accept'
      _(result).must_include 'text/vnd.turbo-stream.html'
    end

    it "handles html-only respond_to without turbo check" do
      source = <<~RUBY
        class ArticlesController < ApplicationController
          def create
            @article = Article.new(params)
            respond_to do |format|
              format.html { redirect_to @article }
            end
          end
        end
      RUBY

      result = to_js(source)
      # Should NOT have turbo-stream check when only html format
      _(result).wont_include 'text/vnd.turbo-stream.html'
    end
  end
end
