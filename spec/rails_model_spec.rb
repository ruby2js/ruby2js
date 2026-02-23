require 'minitest/autorun'
require 'ruby2js/filter/rails/model'
require 'ruby2js/filter/esm'
require 'ruby2js/filter/functions'

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

  describe "ActiveRecord::Base subclass" do
    it "imports ActiveRecord from adapter path" do
      result = to_js('class ApplicationRecord < ActiveRecord::Base; end')
      assert_includes result, 'from "../lib/active_record.mjs"'
      assert_includes result, 'import { ActiveRecord'
    end

    it "extends ActiveRecord (not ActiveRecord.Base)" do
      result = to_js('class ApplicationRecord < ActiveRecord::Base; end')
      assert_includes result, 'class ApplicationRecord extends ActiveRecord'
      refute_includes result, 'ActiveRecord.Base'
    end

    it "re-exports utility classes" do
      result = to_js('class ApplicationRecord < ActiveRecord::Base; end')
      assert_includes result, 'export { CollectionProxy, modelRegistry, Reference, HasOneReference }'
    end

    it "strips primary_abstract_class" do
      result = to_js(<<~RUBY)
        class ApplicationRecord < ActiveRecord::Base
          primary_abstract_class
        end
      RUBY
      refute_includes result, 'primary_abstract_class'
      assert_includes result, 'primaryAbstractClass = true'
    end

    it "skips table_name for abstract classes" do
      result = to_js(<<~RUBY)
        class ApplicationRecord < ActiveRecord::Base
          primary_abstract_class
        end
      RUBY
      refute_includes result, 'table_name'
    end

    it "generates table_name without primary_abstract_class" do
      result = to_js('class ApplicationRecord < ActiveRecord::Base; end')
      assert_includes result, 'table_name = "application_records"'
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
      assert_includes result, ', modelRegistry.Comment)'
    end

    it "imports CollectionProxy and modelRegistry for has_many associations" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          has_many :comments
        end
      RUBY
      assert_includes result, 'import { ApplicationRecord, CollectionProxy, modelRegistry }'
    end

    it "supports class_name option" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          has_many :reviews, class_name: 'Comment'
        end
      RUBY
      assert_includes result, 'get reviews()'
      assert_includes result, 'name: "reviews"'
      assert_includes result, ', modelRegistry.Comment)'
    end

    it "supports nested class_name with :: separator" do
      result = to_js(<<~RUBY)
        class Account < ApplicationRecord
          has_many :exports, class_name: 'Account::Export'
        end
      RUBY
      # No cross-model import — uses modelRegistry for lazy resolution
      refute_includes result, 'import { Export } from'
      # CollectionProxy uses registry lookup with leaf class name (:: stripped)
      assert_includes result, 'modelRegistry.Export'
    end

    it "supports foreign_key option with string" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          has_many :comments, foreign_key: 'post_id'
        end
      RUBY
      assert_includes result, 'foreignKey: "post_id"'
    end

    it "supports foreign_key option with symbol" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          has_many :comments, foreign_key: :post_id
        end
      RUBY
      assert_includes result, 'foreignKey: "post_id"'
      refute_includes result, ':post_id'
    end

    it "handles dependent destroy" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          has_many :comments, dependent: :destroy
        end
      RUBY
      assert_includes result, 'async destroy()'
      # Uses for..of with await to iterate over association
      assert_includes result, 'for (let record of await this.comments)'
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
      # Access via attributes property
      assert_includes result, 'this.attributes.article_id'
      assert_includes result, 'new Reference(modelRegistry.Article'
    end

    it "handles optional: true" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          belongs_to :author, optional: true
        end
      RUBY
      assert_includes result, 'get author()'
      # Should check for nil before finding
      assert_includes result, 'this.attributes.author_id'
      assert_includes result, '?'
    end

    it "supports class_name option" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          belongs_to :creator, class_name: 'User'
        end
      RUBY
      assert_includes result, 'get creator()'
      assert_includes result, 'this.attributes.creator_id'
      assert_includes result, 'new Reference(modelRegistry.User'
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

    it "handles validates_associated" do
      result = to_js(<<~RUBY)
        class Heat < ApplicationRecord
          belongs_to :entry
          validates_associated :entry
        end
      RUBY
      assert_includes result, 'validates_associated_of("entry")'
    end
  end

  describe "scope" do
    it "generates class method for scope" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          scope :published, -> { where(status: 'published') }
        end
      RUBY
      assert_includes result, 'static get published()'
      assert_includes result, 'this.where({status: "published"})'
    end

    it "handles chained scope methods" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          scope :recent, -> { order(created_at: :desc).limit(10) }
        end
      RUBY
      assert_includes result, 'static get recent()'
      assert_includes result, 'this.order({created_at: "desc"}).limit(10)'
    end

    it "simplifies arel_table[:column] to column name string" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          scope :ordered, -> { order(arel_table[:order]) }
          scope :by_name, -> { order(arel_table[:name]) }
        end
      RUBY
      assert_includes result, 'this.order("order")'
      assert_includes result, 'this.order("name")'
      refute_includes result, 'arel_table'
    end
  end

  describe "callbacks" do
    it "registers before_save callback on class" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          before_save :normalize_title

          private

          def normalize_title
            self.title = title.strip
          end
        end
      RUBY
      assert_includes result, 'Article.before_save("normalize_title")'
      assert_includes result, 'normalize_title()'
    end

    it "handles multiple callbacks of same type" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          before_save :method_a, :method_b
        end
      RUBY
      assert_includes result, 'Article.before_save("method_a")'
      assert_includes result, 'Article.before_save("method_b")'
    end

    it "supports after_create callback" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          after_create :notify_subscribers
        end
      RUBY
      assert_includes result, 'Article.after_create("notify_subscribers")'
    end

    it "skips callbacks with if: conditions" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          after_save :upload_blobs, if: -> { counter_art.attached? }
        end
      RUBY
      refute_includes result, 'after_save'
    end

    it "skips callbacks with unless: conditions" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          before_save :check_status, unless: -> { draft? }
        end
      RUBY
      refute_includes result, 'before_save'
    end

    it "generates async callback when accessing associations" do
      result = to_js(<<~RUBY)
        class Comment < ApplicationRecord
          belongs_to :article
          after_create_commit { article.broadcast_replace_to "articles" }
        end
      RUBY
      # Callback should be async because it accesses the association
      assert_includes result, 'async $record =>'
      # Association access should be awaited
      assert_includes result, '(await $record.article)'
      # Method call on awaited association
      assert_includes result, '.broadcast_replace_to'
    end

    it "generates sync callback when not accessing associations" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          after_create_commit { broadcast_append_to "articles" }
        end
      RUBY
      # Callback should NOT be async when not accessing associations
      assert_includes result, '$record =>'
      refute_includes result, 'async $record =>'
    end

    it "supports ActiveRecord::Base as superclass" do
      result = to_js(<<~RUBY)
        class Comment < ActiveRecord::Base
          belongs_to :article
          after_create_commit { article.broadcast_replace_to "articles" }
        end
      RUBY
      # Should detect ActiveRecord::Base as a model superclass
      assert_includes result, 'async $record =>'
      assert_includes result, '(await $record.article)'
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

    it "registers callbacks as post-class statements" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          before_save :normalize_title
        end
      RUBY
      # Callbacks are registered on the class, not as instance methods
      assert_includes result, 'Article.before_save("normalize_title")'
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
      # normalize_title is called by _runCallbacks, should be a method
      assert_includes result, 'normalize_title()'
      refute_includes result, 'get normalize_title'
    end

    it "registers multiple callbacks individually" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          before_save :step_a, :step_b
        end
      RUBY
      # Each callback registered separately for individual invocation
      assert_includes result, 'Article.before_save("step_a")'
      assert_includes result, 'Article.before_save("step_b")'
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
      # Non-remove actions use $record.toHTML() for content
      assert_includes result, '$record.toHTML()'
      assert_includes result, '<template>'
    end

    it "transforms broadcast_json_to with $record receiver" do
      result = to_js(<<~RUBY)
        class Node < ApplicationRecord
          after_create_commit do
            broadcast_json_to "workflow_\#{workflow_id}", "node_created"
          end
        end
      RUBY
      # Uses $record. receiver for broadcast calls in callbacks
      assert_includes result, '$record.broadcast_json_to'
      # References workflow_id as $record.workflow_id
      assert_includes result, '$record.workflow_id'
    end

    it "adds $record receiver to bare broadcast calls" do
      result = to_js(<<~RUBY)
        class Edge < ApplicationRecord
          after_destroy_commit do
            broadcast_json_to "workflow_\#{workflow_id}", "edge_destroyed"
          end
        end
      RUBY
      # Callback uses $record parameter (no parens for single arg arrow function)
      assert_includes result, '$record =>'
      # broadcast_json_to gets $record receiver
      assert_includes result, '$record.broadcast_json_to'
    end
  end

  describe "broadcasts_to" do
    it "generates after_create_commit with append" do
      result = to_js(<<~RUBY)
        class Message < ApplicationRecord
          broadcasts_to -> { "chat_room" }
        end
      RUBY
      assert_includes result, 'Message.after_create_commit'
      assert_includes result, 'action="append"'
      # Target as template literal interpolation
      assert_includes result, '"messages"'
    end

    it "generates after_create_commit with prepend when inserts_by: :prepend" do
      result = to_js(<<~RUBY)
        class Message < ApplicationRecord
          broadcasts_to -> { "chat_room" }, inserts_by: :prepend
        end
      RUBY
      assert_includes result, 'Message.after_create_commit'
      assert_includes result, 'action="prepend"'
    end

    it "generates after_update_commit with replace" do
      result = to_js(<<~RUBY)
        class Message < ApplicationRecord
          broadcasts_to -> { "chat_room" }
        end
      RUBY
      assert_includes result, 'Message.after_update_commit'
      assert_includes result, 'action="replace"'
      # Replace uses dom_id for target
      assert_includes result, 'message_${$record.id}'
    end

    it "generates after_destroy_commit with remove" do
      result = to_js(<<~RUBY)
        class Message < ApplicationRecord
          broadcasts_to -> { "chat_room" }
        end
      RUBY
      assert_includes result, 'Message.after_destroy_commit'
      assert_includes result, 'action="remove"'
      # Remove uses dom_id for target
      assert_includes result, 'message_${$record.id}'
    end

    it "uses custom target when specified" do
      result = to_js(<<~RUBY)
        class Message < ApplicationRecord
          broadcasts_to -> { "chat_room" }, target: "chat_messages"
        end
      RUBY
      # Create uses custom target (in template literal)
      assert_includes result, '"chat_messages"'
    end

    it "handles dynamic stream names" do
      result = to_js(<<~RUBY)
        class Comment < ApplicationRecord
          broadcasts_to -> { "article_\#{article_id}_comments" }
        end
      RUBY
      # Dynamic stream via template literal
      assert_includes result, '`article_${'
      assert_includes result, '$record.article_id'
    end

    it "imports BroadcastChannel" do
      result = to_js(<<~RUBY)
        class Message < ApplicationRecord
          broadcasts_to -> { "chat_room" }
        end
      RUBY
      assert_includes result, 'import { BroadcastChannel }'
    end

    it "uses render() for content instead of toHTML()" do
      result = to_js(<<~RUBY)
        class Message < ApplicationRecord
          broadcasts_to -> { "chat_room" }
        end
      RUBY
      # Should use the partial's render function with $context
      assert_includes result, 'await render({'
      assert_includes result, '$context: {authenticityToken: "", flash: {}, contentFor: {}}'
      assert_includes result, 'message: $record'
      # Should import the partial
      assert_includes result, 'import { render } from "../views/messages/_message.js"'
    end

    it "broadcasts to BroadcastChannel" do
      result = to_js(<<~RUBY)
        class Message < ApplicationRecord
          broadcasts_to -> { "chat_room" }
        end
      RUBY
      # Channel name passed to broadcast
      assert_includes result, 'BroadcastChannel.broadcast'
      assert_includes result, '"chat_room"'
    end
  end

  describe "self-referential imports" do
    it "does not import the model being defined" do
      result = to_js(<<~RUBY)
        class Person < ApplicationRecord
          belongs_to :exclude, class_name: 'Person'
        end
      RUBY
      refute_includes result, "import { Person }"
    end
  end

  describe "any? on AR chains" do
    it "converts any? to .any() method call on AR chains" do
      result = to_js('Article.where(status: "published").any?')
      assert_includes result, '.any()'
      refute_includes result, '.length > 0'
    end

    it "preserves any? as .length > 0 on non-AR chains" do
      result = to_js('[1, 2, 3].any?',
        filters: [Ruby2JS::Filter::Rails::Model, Ruby2JS::Filter::Functions])
      assert_includes result, '.length > 0'
    end
  end

  describe "accepts_nested_attributes_for" do
    it "generates setter and static registration for simple case" do
      result = to_js(<<~RUBY)
        class Person < ApplicationRecord
          has_many :answers
          accepts_nested_attributes_for :answers
        end
      RUBY
      assert_includes result, 'set answers_attributes(value)'
      assert_includes result, 'Person.accepts_nested_attributes_for("answers")'
    end

    it "generates setter that stores to _pending_nested_attributes" do
      result = to_js(<<~RUBY)
        class Person < ApplicationRecord
          has_many :answers
          accepts_nested_attributes_for :answers
        end
      RUBY
      assert_includes result, '_pending_nested_attributes'
      assert_includes result, '_pending_nested_attributes.answers = value'
    end

    it "initializes _pending_nested_attributes if not set" do
      result = to_js(<<~RUBY)
        class Person < ApplicationRecord
          has_many :answers
          accepts_nested_attributes_for :answers
        end
      RUBY
      assert_includes result, 'if (!this._pending_nested_attributes) this._pending_nested_attributes = {}'
    end

    it "passes through options like allow_destroy" do
      result = to_js(<<~RUBY)
        class Billable < ApplicationRecord
          has_many :questions
          accepts_nested_attributes_for :questions, allow_destroy: true
        end
      RUBY
      assert_includes result, 'Billable.accepts_nested_attributes_for('
      assert_includes result, '"questions"'
      assert_includes result, 'allow_destroy: true'
    end

    it "passes through reject_if proc" do
      result = to_js(<<~RUBY)
        class Billable < ApplicationRecord
          has_many :questions
          accepts_nested_attributes_for :questions, reject_if: proc { |a| a["question_text"].blank? }
        end
      RUBY
      assert_includes result, 'reject_if'
      assert_includes result, 'question_text'
    end

    it "does not pass through raw DSL call" do
      result = to_js(<<~RUBY)
        class Person < ApplicationRecord
          has_many :answers
          accepts_nested_attributes_for :answers
        end
      RUBY
      # The raw call should not appear as a bare method call in the class body
      # It should only appear as the static registration: Person.accepts_nested_attributes_for(...)
      refute_includes result, 'accepts_nested_attributes_for("answers")'
        .gsub(/^/, '  ') # not indented as class body
      assert_includes result, 'Person.accepts_nested_attributes_for("answers")'
    end
  end

  describe "find_by!" do
    it "converts find_by! to findByBang" do
      result = to_js('Article.find_by!(slug: "hello")')
      assert_includes result, 'findByBang'
      refute_includes result, 'find_by('
    end

    it "passes arguments through to findByBang" do
      result = to_js('Article.find_by!(title: "test", status: "published")')
      assert_includes result, 'findByBang({title: "test", status: "published"})'
    end
  end
end
