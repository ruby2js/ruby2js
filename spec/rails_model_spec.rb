require 'minitest/autorun'
require 'ruby2js/filter/rails/model'
require 'ruby2js/filter/esm'

describe Ruby2JS::Filter::Rails::Model do
  def to_js(string, options = {})
    Ruby2JS.convert(string, {
      filters: [Ruby2JS::Filter::Rails::Model, Ruby2JS::Filter::ESM],
      eslevel: 2020
    }.merge(options)).to_s
  end

  describe "class detection" do
    it "detects ApplicationRecord subclass" do
      result = to_js('class Article < ApplicationRecord; end')
      assert_includes result, 'class Article extends ApplicationRecord'
    end

    it "generates table_name property" do
      result = to_js('class Article < ApplicationRecord; end')
      # Static property assignment (not method)
      assert_includes result, 'table_name = "articles"'
    end

    it "handles irregular plural for table name" do
      result = to_js('class Person < ApplicationRecord; end')
      assert_includes result, '"people"'
    end
  end

  describe "has_many" do
    it "generates association getter" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          has_many :comments
        end
      RUBY
      assert_includes result, 'get comments()'
      assert_includes result, 'Comment.where({article_id: this.id})'
    end

    it "supports class_name option" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          has_many :reviews, class_name: 'Comment'
        end
      RUBY
      assert_includes result, 'get reviews()'
      assert_includes result, 'Comment.where({article_id: this.id})'
    end

    it "supports foreign_key option" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          has_many :comments, foreign_key: 'post_id'
        end
      RUBY
      assert_includes result, 'Comment.where({post_id: this.id})'
    end

    it "handles dependent destroy" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          has_many :comments, dependent: :destroy
        end
      RUBY
      assert_includes result, 'destroy()'
      # Associations are getters, so accessed without parentheses
      assert_includes result, 'this.comments.'
      assert_includes result, '.destroy()'
    end
  end

  describe "belongs_to" do
    it "generates association getter" do
      result = to_js(<<~RUBY)
        class Comment < ApplicationRecord
          belongs_to :article
        end
      RUBY
      assert_includes result, 'get article()'
      # Access via _attributes property with bracket notation
      assert_includes result, 'this._attributes["article_id"'
      assert_includes result, 'Article.find('
    end

    it "handles optional: true" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          belongs_to :author, optional: true
        end
      RUBY
      assert_includes result, 'get author()'
      # Should check for nil before finding
      assert_includes result, 'this._attributes["author_id"'
      assert_includes result, '?'
    end

    it "supports class_name option" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          belongs_to :creator, class_name: 'User'
        end
      RUBY
      assert_includes result, 'get creator()'
      assert_includes result, 'this._attributes["creator_id"'
      assert_includes result, 'User.find('
    end
  end

  describe "validates" do
    it "generates validate method with presence" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          validates :title, presence: true
        end
      RUBY
      assert_includes result, 'validate()'
      assert_includes result, 'validates_presence_of("title")'
    end

    it "handles multiple attributes" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          validates :title, :body, presence: true
        end
      RUBY
      assert_includes result, 'validates_presence_of("title")'
      assert_includes result, 'validates_presence_of("body")'
    end

    it "handles length validation" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          validates :body, length: { minimum: 10 }
        end
      RUBY
      assert_includes result, 'validates_length_of("body", {minimum: 10})'
    end

    it "handles multiple validations on one attribute" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          validates :title, presence: true, length: { minimum: 5, maximum: 100 }
        end
      RUBY
      assert_includes result, 'validates_presence_of("title")'
      assert_includes result, 'validates_length_of("title"'
    end
  end

  describe "scope" do
    it "generates class method for scope" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          scope :published, -> { where(status: 'published') }
        end
      RUBY
      assert_includes result, 'static published()'
      assert_includes result, 'this.where({status: "published"})'
    end

    it "handles chained scope methods" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          scope :recent, -> { order(created_at: :desc).limit(10) }
        end
      RUBY
      assert_includes result, 'static recent()'
      assert_includes result, 'this.order({created_at: "desc"}).limit(10)'
    end
  end

  describe "callbacks" do
    it "generates before_save callback method" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          before_save :normalize_title

          private

          def normalize_title
            self.title = title.strip
          end
        end
      RUBY
      assert_includes result, 'before_save()'
      assert_includes result, 'normalize_title()'
    end

    it "handles multiple callbacks of same type" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          before_save :method_a, :method_b
        end
      RUBY
      assert_includes result, 'before_save()'
      assert_includes result, 'method_a()'
      assert_includes result, 'method_b()'
    end

    it "supports after_create callback" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          after_create :notify_subscribers
        end
      RUBY
      assert_includes result, 'after_create()'
      assert_includes result, 'notify_subscribers()'
    end
  end

  describe "instance methods" do
    it "preserves public instance methods" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          def full_title
            "\#{title} by \#{author}"
          end
        end
      RUBY
      assert_includes result, 'full_title()'
    end
  end

  describe "export" do
    it "exports the class" do
      result = to_js('class Article < ApplicationRecord; end')
      assert_includes result, 'export class Article'
    end
  end
end
