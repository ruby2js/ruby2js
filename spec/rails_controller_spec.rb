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
      # Returns nested params object (AR adapter filters to known columns)
      _(result).must_include 'function article_params(params)'
      _(result).must_include 'params.article ??'
      _(result).must_include 'article_params(params)'
    end

    it "handles Rails 8 params.expect as strong params" do
      source = <<~RUBY
        class ArticlesController < ApplicationController
          def create
            @article = Article.new(article_params)
          end

          private
          def article_params
            params.expect(article: [:title, :body])
          end
        end
      RUBY

      result = to_js(source)
      _(result).must_include 'article_params(params)'
      _(result).must_include 'function article_params(params)'
      _(result).must_include 'params.article ??'
      _(result).wont_include 'expect'
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
      # Each extracts from its own model key
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

    it "handles multi-statement format.html block with redirect_to" do
      source = <<~RUBY
        class PeopleController < ApplicationController
          def update
            respond_to do |format|
              if @person.update(params)
                format.html {
                  redirect_url = params[:return_to].presence || person_url(@person)
                  redirect_to redirect_url, notice: "Updated."
                }
                format.json { render :show }
              end
            end
          end
        end
      RUBY

      result = to_js(source)
      # The redirect hash must be the return value, not the assignment
      _(result).must_match(/return\s*\{[\s\S]*redirect:[\s\S]*notice:/)
      # Assignment should NOT have return
      _(result).wont_match(/return\s+redirect_url\s*=/)
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
      _(result).must_match(/return\s*\{[\s\S]*redirect:\s*heats_path\(\)/)
      _(result).must_match(/return\s*\{[\s\S]*redirect:\s*categories_path\(\)/)
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

    it "normalizes _url helpers to _path" do
      source = <<~RUBY
        class StudiosController < ApplicationController
          def unpair
            redirect_to edit_studio_url(@studio), notice: "unpaired"
          end
          def destroy
            redirect_to studios_url, status: 303
          end
        end
      RUBY

      result = to_js(source)
      _(result).must_include 'edit_studio_path'
      _(result).must_include 'studios_path()'
      _(result).wont_include '_url'
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
      # Private method receives ivar-derived locals as arguments
      _(result).must_include 'setup_heatlist_data(heats)'
      _(result).must_include 'function setup_heatlist_data(heats)'
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

    it "does not import ENV, ARGV, or stdio globals as models" do
      source = <<~RUBY
        class ToolsController < ApplicationController
          def show
            @path = ENV.fetch("RAILS_DB_VOLUME", "db")
            STDOUT.write("debug")
          end
        end
      RUBY

      result = to_js(source)
      _(result).wont_include 'import { Env }'
      _(result).wont_include 'import { Stdout }'
      # ENV and STDOUT remain as-is (node target filter converts ENV to process.env)
      _(result).must_include 'ENV.fetch'
    end

    it "does not duplicate import for require_relative constants" do
      source = <<~RUBY
        require_relative '../../lib/erb_prism_converter'

        class TemplatesController < ApplicationController
          def scoring
            @converter = ErbPrismConverter.new("test")
          end
        end
      RUBY

      result = to_js(source)
      # Should not auto-import ErbPrismConverter since it's already required
      _(result).wont_include 'import([ErbPrismConverter]'
    end

    it "transforms class variables to closure-scoped locals in IIFE" do
      source = <<~RUBY
        class WidgetsController < ApplicationController
          def show
            @token = @@encryptor.sign(@widget)
          end

          @@encryptor = ActiveSupport::MessageEncryptor.new("key")
        end
      RUBY

      result = to_js(source)
      # Class variable assignment becomes let at IIFE scope
      _(result).must_include 'let encryptor = new ActiveSupport'
      # Class variable reference in action becomes plain variable
      _(result).must_include 'encryptor.sign'
      # Should NOT have private field syntax
      _(result).wont_include '#$encryptor'
      _(result).wont_include 'this.constructor'
    end

    it "handles multi-statement format.json blocks in respond_to" do
      source = <<~RUBY
        class ItemsController < ApplicationController
          def create
            @item = Item.new(params)
            respond_to do |format|
              format.html
              format.json {
                ItemJob.perform_later(@item.id)
                render json: @item
              }
            end
          end
        end
      RUBY

      result = to_js(source)
      # Preceding statement should be outside the json return
      _(result).must_include 'ItemJob.perform_later'
      # Return should wrap only the render value
      _(result).must_include '{json: item}'
      # The job call should NOT be inside the {json: ...} wrapper
      _(result).wont_include '{json: ItemJob'
    end
  end

  describe 'private methods with async operations' do
    it "makes private methods async when they contain AR queries" do
      source = <<~RUBY
        class BillablesController < ApplicationController
          def edit
            @billable = Billable.find(params[:id])
            setup_form
          end

          private

          def setup_form
            @options = Billable.where(type: 'Option').map {|o| [o, true]}
          end
        end
      RUBY

      result = to_js(source)
      # Private method receives ivar-derived locals as arguments
      _(result).must_include 'async function setup_form(options)'
    end
  end

  describe 'find with block vs AR find' do
    it "does not add await to find with a block (Enumerable#find)" do
      source = <<~RUBY
        class AdminController < ApplicationController
          def regions
            @deployed = data['ProcessGroupRegions'].
              find {|process| process['Name'] == 'app'}
          end
        end
      RUBY

      result = to_js(source)
      _(result).wont_include 'await data'
      _(result).must_include '.find('
    end

    it "does not add await to hash subscript chains" do
      source = <<~RUBY
        class AdminController < ApplicationController
          def show
            @item = config['items'].first
          end
        end
      RUBY

      result = to_js(source)
      _(result).wont_include 'await config'
    end

    it "still adds await to association find without block" do
      source = <<~RUBY
        class ArticlesController < ApplicationController
          def show
            @comment = @article.comments.find(params[:id])
          end
        end
      RUBY

      result = to_js(source)
      _(result).must_include 'await'
    end
  end

  describe 'AR chain with .or() strips inner awaits' do
    it "does not individually await intermediate where() calls in a chain" do
      source = <<~RUBY
        class StudiosController < ApplicationController
          def unpair
            StudioPair.where(studio1: @studio, studio2: pair_studio)
              .or(StudioPair.where(studio1: pair_studio, studio2: @studio))
              .destroy_all
          end
        end
      RUBY

      result = to_js(source)
      # The whole chain should have ONE outer await on destroy_all
      _(result).must_include 'await'
      _(result).must_include '.destroy_all()'
      # Inner where() calls should NOT be individually awaited
      # (awaiting a Relation resolves it to Array, breaking .or())
      _(result).wont_include 'await StudioPair.where'
      _(result).wont_include 'await (await'
      _(result).must_include '.or(StudioPair.where('
    end
  end

  describe 'private method autoreturn' do
    it "adds return to hash literal as last expression" do
      source = <<~RUBY
        class ScoresController < ApplicationController
          def show
            @data = student_results
          end

          private

          def student_results
            {followers: 1, leaders: 2}
          end
        end
      RUBY

      result = to_js(source)
      _(result).must_include 'return {followers: 1, leaders: 2}'
    end
  end

  describe 'class methods (def self.foo)' do
    it "emits getter/setter accessor syntax on return object" do
      source = <<~RUBY
        class EventController < ApplicationController
          def self.logo
            @@logo ||= 'default.png'
          end

          def self.logo=(logo)
            @@logo = logo
          end

          def index
            EventController.logo = 'new.png'
          end
        end
      RUBY

      result = to_js(source)
      _(result).must_include 'get logo()'
      _(result).must_include 'set logo('
      # Setter parameter must not shadow the closure variable
      _(result).wont_include 'set logo(logo)'
      _(result).must_include 'set logo(_logo)'
      # Caller should use ControllerName.prop = val syntax
      _(result).must_include 'EventController.logo = "new.png"'
      _(result).wont_include 'set_logo('
    end

    it "preserves getter class method calls via ControllerName.prop" do
      source = <<~RUBY
        class EventController < ApplicationController
          def self.logo
            @@logo ||= 'default.png'
          end

          def self.logo=(logo)
            @@logo = logo
          end

          def show
            @current_logo = EventController.logo
          end
        end
      RUBY

      result = to_js(source)
      _(result).must_include 'EventController.logo'
      _(result).must_include 'get logo()'
    end

    it "declares closure variable when no class-level @@cvar exists" do
      source = <<~RUBY
        class EventController < ApplicationController
          def self.logo
            @@logo ||= 'default.png'
          end

          def self.logo=(logo)
            @@logo = logo == '' ? nil : logo
          end

          def show
            EventController.logo = 'new.png'
          end
        end
      RUBY

      result = to_js(source)
      # Should add `let logo` declaration at IIFE scope even without @@logo = nil
      _(result).must_include 'let logo'
      # Setter must assign to closure variable, not declare a new local
      _(result).wont_include 'let logo ='
      _(result).must_include 'logo = _logo'
    end

    it "keeps non-accessor class methods as bare calls" do
      source = <<~RUBY
        class TestController < ApplicationController
          def self.version
            "1.0"
          end

          def show
            v = TestController.version
          end
        end
      RUBY

      result = to_js(source)
      _(result).must_include 'function version()'
      _(result).must_include 'version()'
      _(result).wont_include 'get version'
    end
  end

  describe 'private method calls in private methods' do
    it "marks bare private method calls with parens" do
      source = <<~RUBY
        class ScoresController < ApplicationController
          def show
            generate_agenda unless @agenda
          end

          private

          def generate_agenda
            @agenda = 'test'
          end

          def generate_scores
            generate_agenda unless @agenda
            @scores = 'data'
          end
        end
      RUBY

      result = to_js(source)
      # Both action and private method should have parens on the call
      # generate_agenda receives ivar-derived locals as arguments
      _(result).must_include 'generate_agenda(agenda)'
      _(result).must_include 'function generate_agenda(agenda)'
      # In generate_scores, the bare call should also have parens with args
      _(result).must_include 'if (!agenda) generate_agenda(agenda)'
    end
  end

  describe 'multi-statement reject block' do
    it "negates only the last statement in reject block" do
      source = <<~RUBY
        class PeopleController < ApplicationController
          def show
            @strike = @people.reject do |person|
              person_option = PersonOption.find_by(person_id: person.id)
              person_option.present?
            end
          end
        end
      RUBY

      result = to_js(source)
      _(result).must_include '.filter('
      _(result).must_include 'return !(person_option.present)'
      _(result).wont_include '!(person_option = '
    end
  end
end
