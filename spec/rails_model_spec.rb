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
    it "generates association getter with CollectionProxy" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          has_many :comments
        end
      RUBY
      assert_includes result, 'get comments()'
      # Returns CollectionProxy with association metadata
      assert_includes result, 'new CollectionProxy(this'
      assert_includes result, 'name: "comments"'
      assert_includes result, 'type: "has_many"'
      assert_includes result, 'foreignKey: "article_id"'
      assert_includes result, ', Comment)'
    end

    it "imports CollectionProxy for has_many associations" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          has_many :comments
        end
      RUBY
      assert_includes result, 'import { ApplicationRecord, CollectionProxy }'
    end

    it "supports class_name option" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          has_many :reviews, class_name: 'Comment'
        end
      RUBY
      assert_includes result, 'get reviews()'
      assert_includes result, 'name: "reviews"'
      assert_includes result, ', Comment)'
    end

    it "supports foreign_key option" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          has_many :comments, foreign_key: 'post_id'
        end
      RUBY
      assert_includes result, 'foreignKey: "post_id"'
    end

    it "handles dependent destroy" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          has_many :comments, dependent: :destroy
        end
      RUBY
      assert_includes result, 'async destroy()'
      # Uses for..of with await to iterate over association
      assert_includes result, 'for (let record of await(this.comments))'
      assert_includes result, 'await record.destroy()'
    end

    it "caches CollectionProxy in getter" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          has_many :comments
        end
      RUBY
      # Returns cached proxy if available
      assert_includes result, 'if (this._comments) return this._comments'
    end

    it "generates setter for preloading" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          has_many :comments
        end
      RUBY
      assert_includes result, 'set comments(value)'
      assert_includes result, 'this._comments = value'
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
      # Access via attributes property with bracket notation
      assert_includes result, 'this.attributes["article_id"'
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
      assert_includes result, 'this.attributes["author_id"'
      assert_includes result, '?'
    end

    it "supports class_name option" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          belongs_to :creator, class_name: 'User'
        end
      RUBY
      assert_includes result, 'get creator()'
      assert_includes result, 'this.attributes["creator_id"'
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
    it "preserves public instance methods as getters by default" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          def full_title
            "\#{title} by \#{author}"
          end
        end
      RUBY
      # Simple property accessors should be getters
      assert_includes result, 'get full_title()'
    end
  end

  describe "getter vs method handling" do
    it "generates validate as a method not a getter" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          validates :title, presence: true
        end
      RUBY
      # validate() is called by the framework, should be a method
      assert_includes result, 'validate()'
      refute_includes result, 'get validate'
    end

    it "generates callback invokers as methods" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          before_save :normalize_title
        end
      RUBY
      # before_save() is called by the framework, should be a method
      assert_includes result, 'before_save()'
      refute_includes result, 'get before_save'
    end

    it "generates callback implementation methods as methods" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          before_save :normalize_title

          private

          def normalize_title
            self.title = title.strip
          end
        end
      RUBY
      # normalize_title is called by before_save, should be a method
      assert_includes result, 'normalize_title()'
      refute_includes result, 'get normalize_title'
    end

    it "calls callback methods with parentheses" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          before_save :step_a, :step_b
        end
      RUBY
      # Callback method calls should have parentheses
      assert_includes result, 'this.step_a()'
      assert_includes result, 'this.step_b()'
    end
  end

  describe "export" do
    it "exports the class" do
      result = to_js('class Article < ApplicationRecord; end')
      assert_includes result, 'export class Article'
    end
  end

  describe "broadcast methods" do
    it "transforms broadcast_append_to" do
      result = to_js(<<~RUBY)
        class Comment < ApplicationRecord
          after_create_commit do
            broadcast_append_to "comments", target: "comments"
          end
        end
      RUBY
      assert_includes result, 'BroadcastChannel.broadcast'
      assert_includes result, '"comments"'
      assert_includes result, '<turbo-stream action="append" target="comments">'
    end

    it "transforms broadcast_replace_to" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          after_update_commit do
            broadcast_replace_to "articles", target: "article_1"
          end
        end
      RUBY
      assert_includes result, 'BroadcastChannel.broadcast'
      assert_includes result, '"articles"'
      assert_includes result, '<turbo-stream action="replace" target="article_1">'
    end

    it "transforms broadcast_remove_to" do
      result = to_js(<<~RUBY)
        class Comment < ApplicationRecord
          after_destroy_commit do
            broadcast_remove_to "comments", target: "comment_1"
          end
        end
      RUBY
      assert_includes result, 'BroadcastChannel.broadcast'
      assert_includes result, 'action=\\"remove\\"'
      assert_includes result, 'target=\\"comment_1\\"'
      # remove doesn't need template
      refute_includes result, '<template>'
    end

    it "transforms broadcast_prepend_to" do
      result = to_js(<<~RUBY)
        class Comment < ApplicationRecord
          after_create_commit do
            broadcast_prepend_to "comments", target: "comments"
          end
        end
      RUBY
      assert_includes result, 'action="prepend"'
    end

    it "transforms broadcast_update_to" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          after_save_commit do
            broadcast_update_to "articles", target: "article_content"
          end
        end
      RUBY
      assert_includes result, 'action="update"'
    end

    it "transforms broadcast_*_later_to with setTimeout" do
      result = to_js(<<~RUBY)
        class Comment < ApplicationRecord
          after_create_commit do
            broadcast_append_later_to "comments", target: "comments"
          end
        end
      RUBY
      assert_includes result, 'setTimeout'
      assert_includes result, 'BroadcastChannel.broadcast'
    end

    it "handles dynamic channel names" do
      result = to_js(<<~RUBY)
        class Comment < ApplicationRecord
          after_create_commit do
            broadcast_append_to "article_\#{article_id}_comments", target: "comments"
          end
        end
      RUBY
      # Dynamic channel via template literal
      assert_includes result, '`article_${'
    end

    it "handles symbol target" do
      result = to_js(<<~RUBY)
        class Comment < ApplicationRecord
          after_create_commit do
            broadcast_append_to "comments", target: :comments
          end
        end
      RUBY
      assert_includes result, 'target="comments"'
    end

    it "generates toHTML call for content" do
      result = to_js(<<~RUBY)
        class Comment < ApplicationRecord
          after_create_commit do
            broadcast_append_to "comments", target: "comments"
          end
        end
      RUBY
      # Non-remove actions use record.toHTML() for content
      assert_includes result, 'record.toHTML()'
      assert_includes result, '<template>'
    end
  end
end
