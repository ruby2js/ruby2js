require 'minitest/autorun'
require 'ruby2js/filter/rails/test'

describe Ruby2JS::Filter::Rails::Test do
  def to_js(string, options = {})
    Ruby2JS.convert(string, {
      filters: [Ruby2JS::Filter::Rails::Test],
      eslevel: 2020,
      file: 'test/articles_test.rb'  # Ensure filter recognizes as test file
    }.merge(options)).to_s
  end

  describe "detection" do
    it "only transforms test files" do
      # Non-test file should not be transformed
      code = <<~RUBY
        describe "Article Model" do
          it "does something" do
            Article.create(title: "Test")
          end
        end
      RUBY
      result = Ruby2JS.convert(code, {
        filters: [Ruby2JS::Filter::Rails::Test],
        eslevel: 2020,
        file: 'app/models/article.rb'
      }).to_s
      # Should not add async since it's not a test file
      refute_includes result, 'async'
    end

    it "transforms test files by path" do
      result = to_js(<<~RUBY)
        describe "Article Model" do
          it "does something" do
            x = 1
          end
        end
      RUBY
      assert_includes result, 'async'
    end
  end

  describe "describe blocks" do
    it "converts describe blocks to arrow functions" do
      result = to_js(<<~RUBY)
        describe "Article Model" do
          it "works" do
            true
          end
        end
      RUBY
      assert_includes result, 'describe("Article Model"'
      assert_includes result, '() =>'
    end

    it "handles nested describe blocks" do
      result = to_js(<<~RUBY)
        describe "Article" do
          describe "validations" do
            it "validates presence" do
              true
            end
          end
        end
      RUBY
      assert_includes result, 'describe("Article"'
      # Inner describe may have formatting differences
      assert_includes result, '"validations"'
    end
  end

  describe "it blocks" do
    it "converts it blocks to async arrow functions" do
      result = to_js(<<~RUBY)
        describe "test" do
          it "does something" do
            x = 1
          end
        end
      RUBY
      assert_includes result, 'it("does something", async () =>'
    end

    it "handles specify as alias for it" do
      result = to_js(<<~RUBY)
        describe "test" do
          specify "does something" do
            x = 1
          end
        end
      RUBY
      assert_includes result, 'test("does something", async () =>'
    end
  end

  describe "before/after hooks" do
    it "converts before to beforeEach" do
      result = to_js(<<~RUBY)
        describe "test" do
          before do
            @x = 1
          end
          it "works" do
            true
          end
        end
      RUBY
      assert_includes result, 'beforeEach(async () =>'
    end

    it "converts before(:all) to beforeAll" do
      result = to_js(<<~RUBY)
        describe "test" do
          before(:all) do
            @x = 1
          end
          it "works" do
            true
          end
        end
      RUBY
      assert_includes result, 'beforeAll(async () =>'
    end

    it "converts after to afterEach" do
      result = to_js(<<~RUBY)
        describe "test" do
          after do
            cleanup
          end
          it "works" do
            true
          end
        end
      RUBY
      assert_includes result, 'afterEach(async () =>'
    end

    it "converts after(:all) to afterAll" do
      result = to_js(<<~RUBY)
        describe "test" do
          after(:all) do
            cleanup
          end
          it "works" do
            true
          end
        end
      RUBY
      assert_includes result, 'afterAll(async () =>'
    end
  end

  describe "ActiveRecord await wrapping" do
    it "wraps class method calls with await" do
      result = to_js(<<~RUBY)
        describe "test" do
          it "creates" do
            article = Article.create(title: "Test")
          end
        end
      RUBY
      assert_includes result, 'await Article.create'
    end

    it "wraps find with await" do
      result = to_js(<<~RUBY)
        describe "test" do
          it "finds" do
            article = Article.find(1)
          end
        end
      RUBY
      assert_includes result, 'await Article.find'
    end

    it "wraps instance save with await" do
      result = to_js(<<~RUBY)
        describe "test" do
          it "saves" do
            article = Article.new
            article.save
          end
        end
      RUBY
      assert_includes result, 'await article.save'
    end

    it "wraps instance update with await" do
      result = to_js(<<~RUBY)
        describe "test" do
          it "updates" do
            article = Article.find(1)
            article.update(title: "New")
          end
        end
      RUBY
      assert_includes result, 'await article.update'
    end

    it "wraps instance destroy with await" do
      result = to_js(<<~RUBY)
        describe "test" do
          it "destroys" do
            article = Article.find(1)
            article.destroy
          end
        end
      RUBY
      assert_includes result, 'await article.destroy'
    end

    it "wraps chained queries with await" do
      result = to_js(<<~RUBY)
        describe "test" do
          it "queries" do
            articles = Article.where(published: true).order(:created_at).first
          end
        end
      RUBY
      assert_includes result, 'await Article.where'
    end

    it "wraps association methods with await" do
      result = to_js(<<~RUBY)
        describe "test" do
          it "uses associations" do
            article = Article.find(1)
            comment = article.comments.create(body: "Nice")
          end
        end
      RUBY
      assert_includes result, 'await article.comments.create'
    end
  end

  describe "assertions" do
    it "preserves minitest assertions" do
      result = to_js(<<~RUBY)
        describe "test" do
          it "asserts" do
            article = Article.create(title: "Test")
            article.id.wont_be_nil
            article.title.must_equal "Test"
          end
        end
      RUBY
      assert_includes result, 'wont_be_nil'
      assert_includes result, 'must_equal("Test")'
    end
  end

  describe "before hooks with AR" do
    it "wraps AR operations in before hooks" do
      result = to_js(<<~RUBY)
        describe "test" do
          before do
            @article = Article.create(title: "Test")
          end
          it "works" do
            found = Article.find(@article.id)
          end
        end
      RUBY
      assert_includes result, 'await Article.create'
      assert_includes result, 'await Article.find'
    end
  end

  describe "class-based test" do
    it "converts test class to describe" do
      result = to_js(<<~RUBY)
        class SongTest < ActiveSupport::TestCase
          test "valid song" do
            assert true
          end
        end
      RUBY
      assert_includes result, 'describe('
      assert_includes result, '"Song"'
      assert_includes result, 'test("valid song"'
    end

    it "strips Test suffix from describe name" do
      result = to_js(<<~RUBY)
        class ArticleTest < ActiveSupport::TestCase
          test "works" do
            true
          end
        end
      RUBY
      assert_includes result, 'describe("Article"'
      refute_includes result, 'ArticleTest'
    end

    it "converts setup to beforeEach" do
      result = to_js(<<~RUBY)
        class SongTest < ActiveSupport::TestCase
          setup do
            @song = Song.create(title: "Test")
          end
          test "works" do
            true
          end
        end
      RUBY
      assert_includes result, 'beforeEach(async () =>'
      assert_includes result, 'await Song.create'
    end

    it "converts teardown to afterEach" do
      result = to_js(<<~RUBY)
        class SongTest < ActiveSupport::TestCase
          teardown do
            @song.destroy
          end
          test "works" do
            true
          end
        end
      RUBY
      assert_includes result, 'afterEach(async () =>'
    end

    it "wraps AR operations in test blocks" do
      result = to_js(<<~RUBY)
        class SongTest < ActiveSupport::TestCase
          test "creates" do
            song = Song.create(title: "Test")
          end
        end
      RUBY
      assert_includes result, 'await Song.create'
    end

    it "recognizes various test superclasses" do
      result = to_js(<<~RUBY)
        class FooTest < Minitest::Test
          test "works" do
            true
          end
        end
      RUBY
      assert_includes result, 'describe("Foo"'
    end
  end

  describe "require test_helper stripping" do
    it "strips require test_helper" do
      result = to_js(<<~RUBY)
        require "test_helper"
        class SongTest < ActiveSupport::TestCase
          test "works" do
            true
          end
        end
      RUBY
      refute_includes result, 'require'
      refute_includes result, 'test_helper'
      assert_includes result, 'describe("Song"'
    end
  end

  describe "assertion transforms" do
    it "converts assert to expect().toBeTruthy()" do
      result = to_js(<<~RUBY)
        class FooTest < ActiveSupport::TestCase
          test "asserts" do
            assert x
          end
        end
      RUBY
      assert_includes result, 'expect(x).toBeTruthy()'
    end

    it "converts assert_not to expect().toBeFalsy()" do
      result = to_js(<<~RUBY)
        class FooTest < ActiveSupport::TestCase
          test "refutes" do
            assert_not x
          end
        end
      RUBY
      assert_includes result, 'expect(x).toBeFalsy()'
    end

    it "converts refute to expect().toBeFalsy()" do
      result = to_js(<<~RUBY)
        class FooTest < ActiveSupport::TestCase
          test "refutes" do
            refute x
          end
        end
      RUBY
      assert_includes result, 'expect(x).toBeFalsy()'
    end

    it "converts assert_equal to expect().toBe()" do
      result = to_js(<<~RUBY)
        class FooTest < ActiveSupport::TestCase
          test "equals" do
            assert_equal "expected", actual
          end
        end
      RUBY
      assert_includes result, 'expect(actual).toBe("expected")'
    end

    it "converts assert_equal with non-primitive to toEqual" do
      result = to_js(<<~RUBY)
        class FooTest < ActiveSupport::TestCase
          test "equals" do
            assert_equal expected_array, actual
          end
        end
      RUBY
      assert_includes result, 'toEqual'
    end

    it "converts assert_nil to expect().toBeNull()" do
      result = to_js(<<~RUBY)
        class FooTest < ActiveSupport::TestCase
          test "nil" do
            assert_nil x
          end
        end
      RUBY
      assert_includes result, 'expect(x).toBeNull()'
    end

    it "converts assert_not_nil to expect().not.toBeNull()" do
      result = to_js(<<~RUBY)
        class FooTest < ActiveSupport::TestCase
          test "not nil" do
            assert_not_nil x
          end
        end
      RUBY
      assert_includes result, 'expect(x).not.toBeNull()'
    end

    it "converts assert_includes to expect().toContain()" do
      result = to_js(<<~RUBY)
        class FooTest < ActiveSupport::TestCase
          test "includes" do
            assert_includes list, item
          end
        end
      RUBY
      assert_includes result, 'expect(list).toContain(item)'
    end

    it "converts assert_raises to expect().toThrow()" do
      result = to_js(<<~RUBY)
        class FooTest < ActiveSupport::TestCase
          test "raises" do
            assert_raises StandardError do
              Song.create!(title: nil)
            end
          end
        end
      RUBY
      assert_includes result, 'expect(async () =>'
      assert_includes result, '.toThrow(StandardError)'
    end

    it "converts assert_respond_to to typeof check" do
      result = to_js(<<~RUBY)
        class FooTest < ActiveSupport::TestCase
          test "responds" do
            assert_respond_to obj, :title
          end
        end
      RUBY
      assert_includes result, 'expect(typeof obj.title).toBe("function")'
    end

    it "converts assert_empty to toHaveLength(0)" do
      result = to_js(<<~RUBY)
        class FooTest < ActiveSupport::TestCase
          test "empty" do
            assert_empty list
          end
        end
      RUBY
      assert_includes result, 'expect(list).toHaveLength(0)'
    end

    it "converts assert_match to toMatch" do
      result = to_js(<<~RUBY)
        class FooTest < ActiveSupport::TestCase
          test "matches" do
            assert_match /pattern/, str
          end
        end
      RUBY
      assert_includes result, 'expect(str).toMatch(/pattern/)'
    end
  end

  describe "fixture references" do
    it "converts symbol arg to string" do
      result = to_js(<<~RUBY)
        class SongTest < ActiveSupport::TestCase
          test "uses fixture" do
            song = songs(:one)
          end
        end
      RUBY
      assert_includes result, 'songs("one")'
      refute_includes result, ':one'
    end

    it "preserves fixture function call form" do
      result = to_js(<<~RUBY)
        class EntryTest < ActiveSupport::TestCase
          test "uses people fixture" do
            person = people(:Arthur)
          end
        end
      RUBY
      assert_includes result, 'people("Arthur")'
    end
  end

  # ============================================
  # Integration / controller test transforms
  # ============================================

  def to_controller_js(string)
    Ruby2JS.convert(string, {
      filters: [Ruby2JS::Filter::Rails::Test],
      eslevel: 2020,
      file: 'test/controllers/articles_controller_test.rb'
    }).to_s
  end

  describe "integration test class detection" do
    it "converts ActionDispatch::IntegrationTest class to describe" do
      result = to_controller_js(<<~RUBY)
        class ArticlesControllerTest < ActionDispatch::IntegrationTest
          test "works" do
            true
          end
        end
      RUBY
      assert_includes result, 'describe("ArticlesController"'
      refute_includes result, 'ArticlesControllerTest'
    end

    it "does not activate integration transforms for ActiveSupport::TestCase" do
      result = to_js(<<~RUBY)
        class ArticleTest < ActiveSupport::TestCase
          test "works" do
            true
          end
        end
      RUBY
      # Should not include context helper
      refute_includes result, 'function context'
    end
  end

  describe "context helper" do
    it "emits context helper in integration tests" do
      result = to_controller_js(<<~RUBY)
        class ArticlesControllerTest < ActionDispatch::IntegrationTest
          test "works" do
            true
          end
        end
      RUBY
      assert_includes result, 'function context(params = {})'
      assert_includes result, 'flash'
      assert_includes result, 'consumeNotice'
      assert_includes result, 'contentFor'
    end
  end

  describe "HTTP method to controller action" do
    it "converts get plural_url to Controller.index" do
      result = to_controller_js(<<~RUBY)
        class ArticlesControllerTest < ActionDispatch::IntegrationTest
          test "index" do
            get articles_url
          end
        end
      RUBY
      assert_includes result, 'ArticlesController.index(context())'
      assert_includes result, 'let response = await'
    end

    it "converts get singular_url(arg) to Controller.show with id" do
      result = to_controller_js(<<~RUBY)
        class ArticlesControllerTest < ActionDispatch::IntegrationTest
          test "show" do
            get article_url(@article)
          end
        end
      RUBY
      assert_includes result, 'ArticlesController.show(context(), article.id)'
    end

    it "converts get new_singular_url to Controller.$new" do
      result = to_controller_js(<<~RUBY)
        class ArticlesControllerTest < ActionDispatch::IntegrationTest
          test "new" do
            get new_article_url
          end
        end
      RUBY
      assert_includes result, 'ArticlesController.$new(context())'
    end

    it "converts get edit_singular_url(arg) to Controller.edit with id" do
      result = to_controller_js(<<~RUBY)
        class ArticlesControllerTest < ActionDispatch::IntegrationTest
          test "edit" do
            get edit_article_url(@article)
          end
        end
      RUBY
      assert_includes result, 'ArticlesController.edit(context(), article.id)'
    end

    it "converts post plural_url with params to Controller.create" do
      result = to_controller_js(<<~RUBY)
        class ArticlesControllerTest < ActionDispatch::IntegrationTest
          test "create" do
            post articles_url, params: { article: { title: "Test" } }
          end
        end
      RUBY
      assert_includes result, 'ArticlesController.create('
      assert_includes result, 'context()'
      assert_includes result, '{article: {title: "Test"}}'
    end

    it "converts patch singular_url with params to Controller.update" do
      result = to_controller_js(<<~RUBY)
        class ArticlesControllerTest < ActionDispatch::IntegrationTest
          test "update" do
            patch article_url(@article), params: { article: { title: "New" } }
          end
        end
      RUBY
      assert_includes result, 'ArticlesController.update('
      assert_includes result, 'context()'
      assert_includes result, 'article.id'
      assert_includes result, '{article: {title: "New"}}'
    end

    it "converts delete singular_url to Controller.destroy with id" do
      result = to_controller_js(<<~RUBY)
        class ArticlesControllerTest < ActionDispatch::IntegrationTest
          test "destroy" do
            delete article_url(@article)
          end
        end
      RUBY
      assert_includes result, 'ArticlesController.destroy('
      assert_includes result, 'context()'
      assert_includes result, 'article.id'
    end
  end

  describe "assert_response" do
    it "converts assert_response :success to check no redirect" do
      result = to_controller_js(<<~RUBY)
        class ArticlesControllerTest < ActionDispatch::IntegrationTest
          test "success" do
            get articles_url
            assert_response :success
          end
        end
      RUBY
      assert_includes result, 'expect(response.redirect).toBeUndefined()'
    end

    it "converts assert_response :redirect to check redirect present" do
      result = to_controller_js(<<~RUBY)
        class ArticlesControllerTest < ActionDispatch::IntegrationTest
          test "redirect" do
            post articles_url, params: { article: { title: "T" } }
            assert_response :redirect
          end
        end
      RUBY
      assert_includes result, 'expect(response.redirect).toBeDefined()'
    end

    it "converts assert_response :unprocessable_entity to check render present" do
      result = to_controller_js(<<~RUBY)
        class ArticlesControllerTest < ActionDispatch::IntegrationTest
          test "validation error" do
            post articles_url, params: { article: { title: "" } }
            assert_response :unprocessable_entity
          end
        end
      RUBY
      assert_includes result, 'expect(response.render).toBeDefined()'
    end
  end

  describe "assert_redirected_to" do
    it "converts assert_redirected_to with path helper" do
      result = to_controller_js(<<~RUBY)
        class ArticlesControllerTest < ActionDispatch::IntegrationTest
          test "redirect" do
            patch article_url(@article), params: { article: { title: "New" } }
            assert_redirected_to article_url(@article)
          end
        end
      RUBY
      assert_includes result, 'expect(response.redirect).toBe(article_path(article))'
    end

    it "converts assert_redirected_to with plural path" do
      result = to_controller_js(<<~RUBY)
        class ArticlesControllerTest < ActionDispatch::IntegrationTest
          test "redirect to index" do
            delete article_url(@article)
            assert_redirected_to articles_url
          end
        end
      RUBY
      assert_includes result, 'expect(response.redirect).toBe(articles_path())'
    end
  end

  describe "URL to path helper conversion" do
    it "converts articles_url to articles_path()" do
      result = to_controller_js(<<~RUBY)
        class ArticlesControllerTest < ActionDispatch::IntegrationTest
          test "path" do
            assert_redirected_to articles_url
          end
        end
      RUBY
      assert_includes result, 'articles_path()'
    end

    it "converts article_url(obj) to article_path(obj)" do
      result = to_controller_js(<<~RUBY)
        class ArticlesControllerTest < ActionDispatch::IntegrationTest
          test "path" do
            assert_redirected_to article_url(@article)
          end
        end
      RUBY
      assert_includes result, 'article_path(article)'
    end
  end

  describe "instance variable conversion in integration tests" do
    it "converts @article to article in reads" do
      result = to_controller_js(<<~RUBY)
        class ArticlesControllerTest < ActionDispatch::IntegrationTest
          test "ivar" do
            get article_url(@article)
          end
        end
      RUBY
      assert_includes result, 'article.id'
      refute_includes result, '@article'
    end

    it "converts @article = to let article = in setup" do
      result = to_controller_js(<<~RUBY)
        class ArticlesControllerTest < ActionDispatch::IntegrationTest
          setup do
            @article = articles(:one)
          end
          test "works" do
            true
          end
        end
      RUBY
      # Hoisted declaration at describe scope, assignment inside beforeEach
      assert_includes result, 'let article;'
      assert_includes result, 'article = articles("one")'
      refute_includes result, '@article'
    end
  end

  describe "assert_difference" do
    it "transforms assert_difference with default count" do
      result = to_controller_js(<<~RUBY)
        class ArticlesControllerTest < ActionDispatch::IntegrationTest
          test "create" do
            assert_difference("Article.count") do
              post articles_url, params: { article: { title: "Test" } }
            end
          end
        end
      RUBY
      assert_includes result, 'let countBefore = await Article.count()'
      assert_includes result, 'let countAfter = await Article.count()'
      assert_includes result, 'expect(countAfter - countBefore).toBe(1)'
    end

    it "transforms assert_difference with negative count" do
      result = to_controller_js(<<~RUBY)
        class ArticlesControllerTest < ActionDispatch::IntegrationTest
          test "destroy" do
            assert_difference("Article.count", -1) do
              delete article_url(@article)
            end
          end
        end
      RUBY
      assert_includes result, 'expect(countAfter - countBefore).toBe(-1)'
    end

    it "transforms assert_no_difference" do
      result = to_controller_js(<<~RUBY)
        class ArticlesControllerTest < ActionDispatch::IntegrationTest
          test "no change" do
            assert_no_difference("Article.count") do
              post articles_url, params: { article: { title: "" } }
            end
          end
        end
      RUBY
      assert_includes result, 'let countBefore = await Article.count()'
      assert_includes result, 'let countAfter = await Article.count()'
      assert_includes result, 'expect(countAfter - countBefore).toBe(0)'
    end
  end

  describe "full integration test transpilation" do
    it "transpiles a complete controller test" do
      result = to_controller_js(<<~RUBY)
        require "test_helper"
        class ArticlesControllerTest < ActionDispatch::IntegrationTest
          setup do
            @article = articles(:one)
          end

          test "should get index" do
            get articles_url
            assert_response :success
          end

          test "should create article" do
            assert_difference("Article.count") do
              post articles_url, params: { article: { body: @article.body, title: @article.title } }
            end
            assert_redirected_to article_url(Article.last)
          end

          test "should destroy article" do
            assert_difference("Article.count", -1) do
              delete article_url(@article)
            end
            assert_redirected_to articles_url
          end
        end
      RUBY

      # Should have describe block
      assert_includes result, 'describe("ArticlesController"'
      # Should have context helper
      assert_includes result, 'function context(params = {})'
      # Should have fixture setup (hoisted declaration + assignment)
      assert_includes result, 'let article;'
      assert_includes result, 'article = articles("one")'
      # Should not have require or @ivars
      refute_includes result, 'require'
      refute_includes result, 'test_helper'
      refute_includes result, '@article'
    end
  end

  describe "custom collection/member actions" do
    it "converts custom action on collection (redo_heats_url)" do
      result = to_controller_js(<<~RUBY)
        class HeatsControllerTest < ActionDispatch::IntegrationTest
          test "redo" do
            post redo_heats_url
          end
        end
      RUBY
      assert_includes result, 'HeatsController.redo(context())'
    end

    it "converts custom GET action on collection (book_heats_url)" do
      result = to_controller_js(<<~RUBY)
        class HeatsControllerTest < ActionDispatch::IntegrationTest
          test "book" do
            get book_heats_url
          end
        end
      RUBY
      assert_includes result, 'HeatsController.book(context())'
    end

    it "converts multi-word custom action (reset_open_heats_url)" do
      result = to_controller_js(<<~RUBY)
        class HeatsControllerTest < ActionDispatch::IntegrationTest
          test "reset_open" do
            post reset_open_heats_url
          end
        end
      RUBY
      assert_includes result, 'HeatsController.reset_open(context())'
    end
  end

  describe "nested resource URL helpers" do
    it "converts nested plural URL (person_payments_url)" do
      result = to_controller_js(<<~RUBY)
        class PaymentsControllerTest < ActionDispatch::IntegrationTest
          test "index" do
            get person_payments_url(@person)
          end
        end
      RUBY
      assert_includes result, 'PaymentsController.index(context(), person.id)'
    end

    it "converts nested singular URL (person_payment_url)" do
      result = to_controller_js(<<~RUBY)
        class PaymentsControllerTest < ActionDispatch::IntegrationTest
          test "show" do
            get person_payment_url(@person, @payment)
          end
        end
      RUBY
      assert_includes result, 'PaymentsController.show('
      assert_includes result, 'person.id'
      assert_includes result, 'payment.id'
    end

    it "converts nested new URL (new_person_payment_url)" do
      result = to_controller_js(<<~RUBY)
        class PaymentsControllerTest < ActionDispatch::IntegrationTest
          test "new" do
            get new_person_payment_url(@person)
          end
        end
      RUBY
      assert_includes result, 'PaymentsController.$new(context(), person.id)'
    end

    it "converts nested edit URL (edit_person_payment_url)" do
      result = to_controller_js(<<~RUBY)
        class PaymentsControllerTest < ActionDispatch::IntegrationTest
          test "edit" do
            get edit_person_payment_url(@person, @payment)
          end
        end
      RUBY
      assert_includes result, 'PaymentsController.edit('
      assert_includes result, 'person.id'
      assert_includes result, 'payment.id'
    end
  end

  describe "non-standard assert_response codes" do
    it "converts numeric 303 to redirect check" do
      result = to_controller_js(<<~RUBY)
        class FooControllerTest < ActionDispatch::IntegrationTest
          test "303" do
            delete item_url(@item)
            assert_response 303
          end
        end
      RUBY
      assert_includes result, 'expect(response.redirect).toBeDefined()'
    end

    it "converts numeric 422 to render check" do
      result = to_controller_js(<<~RUBY)
        class FooControllerTest < ActionDispatch::IntegrationTest
          test "422" do
            post items_url, params: { item: {} }
            assert_response 422
          end
        end
      RUBY
      assert_includes result, 'expect(response.render).toBeDefined()'
    end

    it "converts assert_response :unprocessable_content to render check" do
      result = to_controller_js(<<~RUBY)
        class FooControllerTest < ActionDispatch::IntegrationTest
          test "422" do
            post items_url, params: { item: {} }
            assert_response :unprocessable_content
          end
        end
      RUBY
      assert_includes result, 'expect(response.render).toBeDefined()'
    end

    it "converts assert_response :no_content to success check" do
      result = to_controller_js(<<~RUBY)
        class FooControllerTest < ActionDispatch::IntegrationTest
          test "204" do
            delete item_url(@item)
            assert_response :no_content
          end
        end
      RUBY
      assert_includes result, 'expect(response.redirect).toBeUndefined()'
    end

    it "converts assert_response :created to success check" do
      result = to_controller_js(<<~RUBY)
        class FooControllerTest < ActionDispatch::IntegrationTest
          test "201" do
            post items_url, params: { item: { name: "x" } }
            assert_response :created
          end
        end
      RUBY
      assert_includes result, 'expect(response.redirect).toBeUndefined()'
    end

    it "converts numeric 200 to success check" do
      result = to_controller_js(<<~RUBY)
        class FooControllerTest < ActionDispatch::IntegrationTest
          test "200" do
            get items_url
            assert_response 200
          end
        end
      RUBY
      assert_includes result, 'expect(response.redirect).toBeUndefined()'
    end
  end

  describe "URL helpers with query params" do
    it "passes hash args on URL helpers as context params" do
      result = to_controller_js(<<~RUBY)
        class HeatsControllerTest < ActionDispatch::IntegrationTest
          test "index with category" do
            get heats_url(cat: 'closed-american-smooth')
          end
        end
      RUBY
      assert_includes result, 'context({cat: "closed-american-smooth"})'
      assert_includes result, 'HeatsController.index('
    end

    it "passes multiple hash args on URL helpers" do
      result = to_controller_js(<<~RUBY)
        class HeatsControllerTest < ActionDispatch::IntegrationTest
          test "book with params" do
            get book_heats_url(type: 'judge', format: 'pdf')
          end
        end
      RUBY
      assert_includes result, 'context({'
      assert_includes result, 'type: "judge"'
      assert_includes result, 'format: "pdf"'
    end

    it "passes URL hash args and request params separately" do
      result = to_controller_js(<<~RUBY)
        class TablesControllerTest < ActionDispatch::IntegrationTest
          test "create with option" do
            post tables_url(option_id: option.id), params: { table: { number: 99 } }
          end
        end
      RUBY
      assert_includes result, 'context({option_id: option.id})'
      assert_includes result, '{table: {number: 99}}'
    end

    it "converts as: :turbo_stream to format context param" do
      result = to_controller_js(<<~RUBY)
        class CategoriesControllerTest < ActionDispatch::IntegrationTest
          test "drop" do
            post drop_categories_url, as: :turbo_stream, params: { source: 1, target: 2 }
          end
        end
      RUBY
      assert_includes result, 'context({format: "turbo_stream"})'
      assert_includes result, '{source: 1, target: 2}'
    end

    it "converts as: :json to format context param" do
      result = to_controller_js(<<~RUBY)
        class ScoresControllerTest < ActionDispatch::IntegrationTest
          test "batch" do
            post scores_url, params: { scores: [] }, as: :json
          end
        end
      RUBY
      assert_includes result, 'context({format: "json"})'
    end
  end

  describe "flash assertions" do
    it "transforms flash[:notice] to _flash.notice" do
      result = to_controller_js(<<~RUBY)
        class ArticlesControllerTest < ActionDispatch::IntegrationTest
          test "flash" do
            post articles_url, params: { article: { title: "Test" } }
            assert_equal 'Article created.', flash[:notice]
          end
        end
      RUBY
      assert_includes result, 'expect(_flash.notice).toBe("Article created.")'
    end

    it "transforms flash[:alert] to _flash.alert" do
      result = to_controller_js(<<~RUBY)
        class ArticlesControllerTest < ActionDispatch::IntegrationTest
          test "flash alert" do
            post articles_url, params: { article: { title: "" } }
            assert_equal "Error", flash[:alert]
          end
        end
      RUBY
      assert_includes result, '_flash.alert'
    end

    it "works with assert_match on flash" do
      result = to_controller_js(<<~RUBY)
        class ArticlesControllerTest < ActionDispatch::IntegrationTest
          test "flash match" do
            post articles_url, params: { article: { title: "Test" } }
            assert_match /created|updated/, flash[:notice]
          end
        end
      RUBY
      assert_includes result, 'expect(_flash.notice).toMatch'
    end

    it "emits _flash variable declaration in context helper" do
      result = to_controller_js(<<~RUBY)
        class ArticlesControllerTest < ActionDispatch::IntegrationTest
          test "works" do
            true
          end
        end
      RUBY
      assert_includes result, 'let _flash = {}'
      assert_includes result, '_flash = {}'  # reset inside context()
    end

    it "context helper flash stores and retrieves values" do
      result = to_controller_js(<<~RUBY)
        class ArticlesControllerTest < ActionDispatch::IntegrationTest
          test "works" do
            true
          end
        end
      RUBY
      # Flash set method stores values
      assert_includes result, 'set(k, v) {_flash[k] = v}'
      # Flash get method retrieves values
      assert_includes result, 'get(k) {return _flash[k]'
    end
  end

  describe "complex assert_difference patterns" do
    it "handles runtime expression as diff value" do
      result = to_controller_js(<<~RUBY)
        class TablesControllerTest < ActionDispatch::IntegrationTest
          test "reset" do
            assert_difference("Table.count", -Table.count) do
              delete reset_tables_url
            end
          end
        end
      RUBY
      assert_includes result, 'let countBefore = await Table.count()'
      assert_includes result, 'let countAfter = await Table.count()'
      # The diff value should be a processed expression, not a literal
      assert_includes result, 'toBe(-'
    end

    it "handles nested assert_difference blocks" do
      result = to_controller_js(<<~RUBY)
        class FooControllerTest < ActionDispatch::IntegrationTest
          test "nested" do
            assert_difference("Solo.count") do
              assert_difference("Heat.count") do
                post heats_url, params: { heat: { dance_id: 1 } }
              end
            end
          end
        end
      RUBY
      # Should have unique variable names for inner and outer
      assert_includes result, 'countBefore'
      assert_includes result, 'countAfter'
      assert_includes result, 'Solo.count()'
      assert_includes result, 'Heat.count()'
    end
  end
end
