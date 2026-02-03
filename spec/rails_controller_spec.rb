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
      _(result).must_include 'renderView(ArticleViews.index, {$context: context, articles})'
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
      _(result).must_include 'new Article(article_params(params))'
      # Strong params emitted as destructuring function
      _(result).must_include 'function article_params(params)'
      _(result).wont_include 'require'
      _(result).wont_include 'permit'
    end

    it "does not inline non-strong-params methods ending in _params" do
      source = <<~RUBY
        class BillablesController < ApplicationController
          def create
            params_to_save = process_question_params(params)
          end

          private

          def process_question_params(params)
            return params unless params[:questions_attributes]
            params
          end
        end
      RUBY

      result = to_js(source)
      # Should NOT inline - process_question_params is not a strong params method
      _(result).must_include 'process_question_params(params)'
      # The method should be emitted as a module function
      _(result).must_include 'function process_question_params(params)'
    end

    it "generates destructuring function for strong params" do
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
      # Extracts from params.article with nullish coalescing
      _(result).must_include 'params.article ??'
      # Returns only permitted keys
      _(result).must_include '_article.title'
      _(result).must_include '_article.body'
    end

    it "handles nested params in strong params (options: {}, arrays)" do
      source = <<~RUBY
        class BillablesController < ApplicationController
          def create
            @billable = Billable.new(billable_params)
          end

          private
          def billable_params
            params.require(:billable).permit(:name, :price, options: {}, questions_attributes: [:id, :text])
          end
        end
      RUBY

      result = to_js(source)
      _(result).must_include 'function billable_params(params)'
      _(result).must_include 'params.billable ??'
      # Simple keys extracted
      _(result).must_include '_billable.name'
      _(result).must_include '_billable.price'
      # Nested keys also extracted
      _(result).must_include '_billable.options'
      _(result).must_include '_billable.questions_attributes'
    end

    it "handles multiple strong params methods in one controller" do
      source = <<~RUBY
        class LocationsController < ApplicationController
          def create
            @location = Location.new(location_params)
            @user = User.new(user_params)
          end

          private
          def location_params
            params.require(:location).permit(:key, :name)
          end

          def user_params
            params.require(:user).permit(:userid, :email)
          end
        end
      RUBY

      result = to_js(source)
      # Each extracts from its own key
      _(result).must_include 'function location_params(params)'
      _(result).must_include 'params.location ??'
      _(result).must_include 'function user_params(params)'
      _(result).must_include 'params.user ??'
      # Call sites preserved
      _(result).must_include 'location_params(params)'
      _(result).must_include 'user_params(params)'
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
      _(result).must_include 'article.update(article_params(params))'
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
      # Now uses path helper instead of hardcoded path (respects base path config)
      _(result).must_include '{redirect: articles_path()}'
      _(result).must_include 'import([articles_path],' # path helper is imported
    end

    it "converts redirect_to @model to path helper call" do
      source = <<~RUBY
        class ArticlesController < ApplicationController
          def create
            @article = Article.new
            redirect_to @article
          end
        end
      RUBY

      result = to_js(source)
      # Now uses path helper instead of hardcoded path (respects base path config)
      _(result).must_include '{redirect: article_path(article)}'
      _(result).must_include 'import([article_path]' # path helper is imported
    end

    it "transforms ivars in path helper arguments" do
      source = <<~RUBY
        class ArticlesController < ApplicationController
          def create
            @article = Article.new
            redirect_to article_path(@article)
          end
        end
      RUBY

      result = to_js(source)
      _(result).must_include '{redirect: article_path(article)}'
      _(result).wont_include '@article'
      _(result).wont_include 'this.#article'  # Not private field
    end

    it "transforms ivars in redirect_to notice messages" do
      source = <<~RUBY
        class ArticlesController < ApplicationController
          def create
            @total = 5
            redirect_to articles_path, notice: "\#{@total} articles created"
          end
        end
      RUBY

      result = to_js(source)
      _(result).must_include '${total} articles created'
      _(result).wont_include '@total'
      _(result).wont_include 'this.#total'  # Not private field
    end

    it "does not double-return redirect_to inside respond_to" do
      source = <<~RUBY
        class CategoriesController < ApplicationController
          def create
            @category = Category.new(params)
            if @category.save
              respond_to do |format|
                format.html { redirect_to categories_url, notice: "Created." }
                format.json { render :show }
              end
            end
          end
        end
      RUBY

      result = to_js(source)
      _(result).wont_include 'return return'
      _(result).must_match(/return\s*\{[\s\S]*redirect:/)
    end

    it "wraps redirect_to inside if/else with return" do
      # redirect_to inside a conditional (not respond_to) also needs return
      source = <<~RUBY
        class CategoriesController < ApplicationController
          def toggle_lock
            if id
              redirect_to heats_url
            else
              redirect_to categories_url
            end
          end
        end
      RUBY

      result = to_js(source)
      _(result).wont_include 'return return'
      # Both branches should have return
      _(result).must_match(/return\s*\{[\s\S]*redirect:\s*heats_url/)
      _(result).must_match(/return\s*\{[\s\S]*redirect:\s*categories_url/)
    end

    it "wraps standalone redirect_to with return statement" do
      # redirect_to outside respond_to block needs explicit return
      # Without return, JS parses bare { key: value } as labeled block statement
      source = <<~RUBY
        class HeatsController < ApplicationController
          def clean
            scratched_count = 5
            redirect_to heats_url, notice: "\#{scratched_count} heats removed"
          end
        end
      RUBY

      result = to_js(source)
      # Check for return followed by hash (allowing for newlines/formatting)
      _(result).must_match(/return\s*\{[\s\S]*redirect:/)
      # Ensure we don't have bare hash statement (semicolon followed by hash)
      _(result).wont_match(/;\s*\n\s*\{redirect:/)
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

    it "converts render json: @model to return json wrapper" do
      source = <<~RUBY
        class ArticlesController < ApplicationController
          def create
            @article = Article.new
            if @article.save
              render json: @article
            else
              render json: { errors: @article.errors }
            end
          end
        end
      RUBY

      result = to_js(source)
      _(result).must_include '{json: article}'
      _(result).must_include '{json: {errors: article.errors}}'
      _(result).wont_include '{render:'
    end

    it "converts render json: hash to return json wrapper" do
      source = <<~RUBY
        class ArticlesController < ApplicationController
          def create
            @article = Article.new
            render json: { errors: @article.errors }
          end
        end
      RUBY

      result = to_js(source)
      _(result).must_include '{json: {errors: article.errors}}'
      _(result).wont_include '{render:'
    end

    it "wraps render json: in conditionals with return" do
      source = <<~RUBY
        class RecordingsController < ApplicationController
          def upload
            if @recording.save
              render json: { status: 'success' }
            else
              render json: { status: 'error' }
            end
          end
        end
      RUBY

      result = to_js(source)
      _(result).must_match(/return\s*\{json:/)
      _(result).wont_match(/;\s*\n\s*\{json:/)
    end
  end

  describe 'head transformation' do
    it "converts head :ok to return null" do
      source = <<~RUBY
        class ArticlesController < ApplicationController
          def destroy
            @article = Article.find(params[:id])
            @article.destroy
            head :ok
          end
        end
      RUBY

      result = to_js(source)
      # head :ok should become null (no response body)
      _(result).must_include 'return null'
      _(result).wont_include 'head('
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
      _(result).must_include 'renderView(ArticleViews.show, {$context: context, article})'
    end
  end

  describe 'private method calls' do
    it "emits parens for bare private method calls in actions" do
      source = <<~RUBY
        class ScoresController < ApplicationController
          def spa
            @heat_number = params[:heat]
            setup_heatlist_data unless @heat_number
          end

          private

          def setup_heatlist_data
            @heats = Heat.all
          end
        end
      RUBY

      result = to_js(source)
      _(result).must_include 'setup_heatlist_data()'
      _(result).wont_include 'let setup_heatlist_data'
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
      _(result).must_include 'return renderView(ArticleViews.index'
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
      # Should check Accept header (uses optional chaining for safety)
      _(result).must_include 'context?.request?.headers?.accept'
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

    it "generates Accept header check for format.json" do
      source = <<~RUBY
        class ArticlesController < ApplicationController
          def index
            @articles = Article.all
            respond_to do |format|
              format.html
              format.json { render json: @articles }
            end
          end
        end
      RUBY

      result = to_js(source)
      # Should check Accept header for JSON (uses optional chaining for safety)
      _(result).must_include 'context?.request?.headers?.accept'
      _(result).must_include 'application/json'
      # Should return json wrapper for JSON response
      _(result).must_include '{json: articles}'
    end

    it "handles json-only respond_to" do
      source = <<~RUBY
        class ArticlesController < ApplicationController
          def index
            @articles = Article.all
            respond_to do |format|
              format.json { render json: @articles }
            end
          end
        end
      RUBY

      result = to_js(source)
      # Should check Accept header
      _(result).must_include 'application/json'
      _(result).must_include '{json: articles}'
    end

    it "handles html and json respond_to" do
      source = <<~RUBY
        class ArticlesController < ApplicationController
          def show
            @article = Article.find(params[:id])
            respond_to do |format|
              format.html
              format.json { render json: @article }
            end
          end
        end
      RUBY

      result = to_js(source)
      # Should have conditional for JSON
      _(result).must_include 'application/json'
      _(result).must_include '{json: article}'
      # Should have HTML fallback (view call)
      _(result).must_include 'ArticleViews.show'
    end
  end
end
