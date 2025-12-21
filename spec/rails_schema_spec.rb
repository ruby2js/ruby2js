require 'minitest/autorun'
require 'ruby2js/filter/rails/schema'
require 'ruby2js/filter/esm'

describe Ruby2JS::Filter::Rails::Schema do
  def to_js(string, options = {})
    Ruby2JS.convert(string, {
      filters: [Ruby2JS::Filter::Rails::Schema, Ruby2JS::Filter::ESM],
      eslevel: 2020
    }.merge(options)).to_s
  end

  describe "detection" do
    it "detects ActiveRecord::Schema.define block" do
      result = to_js(<<~RUBY)
        ActiveRecord::Schema.define do
          create_table "articles" do |t|
            t.string "title"
          end
        end
      RUBY
      assert_includes result, 'export const Schema'
    end

    it "detects versioned schema block" do
      result = to_js(<<~RUBY)
        ActiveRecord::Schema[7.0].define do
          create_table "articles" do |t|
            t.string "title"
          end
        end
      RUBY
      assert_includes result, 'export const Schema'
    end
  end

  describe "create_table" do
    it "generates CREATE TABLE statement" do
      result = to_js(<<~RUBY)
        ActiveRecord::Schema.define do
          create_table "articles" do |t|
            t.string "title"
          end
        end
      RUBY
      assert_includes result, 'CREATE TABLE IF NOT EXISTS articles'
    end

    it "adds id primary key by default" do
      result = to_js(<<~RUBY)
        ActiveRecord::Schema.define do
          create_table "articles" do |t|
            t.string "title"
          end
        end
      RUBY
      assert_includes result, 'id INTEGER PRIMARY KEY AUTOINCREMENT'
    end
  end

  describe "column types" do
    it "maps string to TEXT" do
      result = to_js(<<~RUBY)
        ActiveRecord::Schema.define do
          create_table "articles" do |t|
            t.string "title"
          end
        end
      RUBY
      assert_includes result, 'title TEXT'
    end

    it "maps text to TEXT" do
      result = to_js(<<~RUBY)
        ActiveRecord::Schema.define do
          create_table "articles" do |t|
            t.text "body"
          end
        end
      RUBY
      assert_includes result, 'body TEXT'
    end

    it "maps integer to INTEGER" do
      result = to_js(<<~RUBY)
        ActiveRecord::Schema.define do
          create_table "articles" do |t|
            t.integer "count"
          end
        end
      RUBY
      assert_includes result, 'count INTEGER'
    end

    it "maps boolean to INTEGER" do
      result = to_js(<<~RUBY)
        ActiveRecord::Schema.define do
          create_table "articles" do |t|
            t.boolean "published"
          end
        end
      RUBY
      assert_includes result, 'published INTEGER'
    end

    it "maps datetime to TEXT" do
      result = to_js(<<~RUBY)
        ActiveRecord::Schema.define do
          create_table "articles" do |t|
            t.datetime "published_at"
          end
        end
      RUBY
      assert_includes result, 'published_at TEXT'
    end

    it "maps float to REAL" do
      result = to_js(<<~RUBY)
        ActiveRecord::Schema.define do
          create_table "articles" do |t|
            t.float "rating"
          end
        end
      RUBY
      assert_includes result, 'rating REAL'
    end
  end

  describe "column options" do
    it "handles null: false" do
      result = to_js(<<~RUBY)
        ActiveRecord::Schema.define do
          create_table "articles" do |t|
            t.string "title", null: false
          end
        end
      RUBY
      assert_includes result, 'title TEXT NOT NULL'
    end

    it "handles default string value" do
      result = to_js(<<~RUBY)
        ActiveRecord::Schema.define do
          create_table "articles" do |t|
            t.string "status", default: "draft"
          end
        end
      RUBY
      assert_includes result, "DEFAULT 'draft'"
    end

    it "handles default integer value" do
      result = to_js(<<~RUBY)
        ActiveRecord::Schema.define do
          create_table "articles" do |t|
            t.integer "count", default: 0
          end
        end
      RUBY
      assert_includes result, 'DEFAULT 0'
    end

    it "handles default boolean value" do
      result = to_js(<<~RUBY)
        ActiveRecord::Schema.define do
          create_table "articles" do |t|
            t.boolean "published", default: false
          end
        end
      RUBY
      assert_includes result, 'DEFAULT 0'
    end
  end

  describe "timestamps" do
    it "adds created_at and updated_at columns" do
      result = to_js(<<~RUBY)
        ActiveRecord::Schema.define do
          create_table "articles" do |t|
            t.string "title"
            t.timestamps
          end
        end
      RUBY
      assert_includes result, 'created_at TEXT'
      assert_includes result, 'updated_at TEXT'
    end
  end

  describe "references" do
    it "creates foreign key column" do
      result = to_js(<<~RUBY)
        ActiveRecord::Schema.define do
          create_table "comments" do |t|
            t.references "article"
          end
        end
      RUBY
      assert_includes result, 'article_id INTEGER'
    end

    it "adds NOT NULL by default" do
      result = to_js(<<~RUBY)
        ActiveRecord::Schema.define do
          create_table "comments" do |t|
            t.references "article"
          end
        end
      RUBY
      assert_includes result, 'article_id INTEGER NOT NULL'
    end

    it "adds foreign key constraint when specified" do
      result = to_js(<<~RUBY)
        ActiveRecord::Schema.define do
          create_table "comments" do |t|
            t.references "article", foreign_key: true
          end
        end
      RUBY
      assert_includes result, 'FOREIGN KEY (article_id) REFERENCES articles(id)'
    end
  end

  describe "add_index" do
    it "creates index on single column" do
      result = to_js(<<~RUBY)
        ActiveRecord::Schema.define do
          create_table "articles" do |t|
            t.string "title"
          end
          add_index "articles", ["title"]
        end
      RUBY
      assert_includes result, 'CREATE INDEX IF NOT EXISTS'
      assert_includes result, 'ON articles(title)'
    end

    it "creates index on multiple columns" do
      result = to_js(<<~RUBY)
        ActiveRecord::Schema.define do
          create_table "articles" do |t|
            t.string "status"
            t.datetime "created_at"
          end
          add_index "articles", ["status", "created_at"]
        end
      RUBY
      assert_includes result, 'ON articles(status, created_at)'
    end

    it "creates unique index when specified" do
      result = to_js(<<~RUBY)
        ActiveRecord::Schema.define do
          create_table "users" do |t|
            t.string "email"
          end
          add_index "users", ["email"], unique: true
        end
      RUBY
      assert_includes result, 'CREATE UNIQUE INDEX'
    end

    it "uses custom index name when specified" do
      result = to_js(<<~RUBY)
        ActiveRecord::Schema.define do
          create_table "articles" do |t|
            t.string "title"
          end
          add_index "articles", ["title"], name: "my_custom_index"
        end
      RUBY
      assert_includes result, 'my_custom_index'
    end
  end

  describe "export" do
    it "exports the Schema module" do
      result = to_js(<<~RUBY)
        ActiveRecord::Schema.define do
          create_table "articles" do |t|
            t.string "title"
          end
        end
      RUBY
      assert_includes result, 'export const Schema'
    end

    it "exports create_tables method" do
      result = to_js(<<~RUBY)
        ActiveRecord::Schema.define do
          create_table "articles" do |t|
            t.string "title"
          end
        end
      RUBY
      assert_includes result, 'function create_tables()'
      assert_includes result, 'return {create_tables}'
    end

    it "imports execSQL from adapter and uses it for SQL execution" do
      result = to_js(<<~RUBY)
        ActiveRecord::Schema.define do
          create_table "articles" do |t|
            t.string "title"
          end
        end
      RUBY
      assert_includes result, 'import { execSQL } from "../lib/active_record.mjs"'
      assert_includes result, 'execSQL('
    end
  end
end
