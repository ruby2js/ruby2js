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
end
