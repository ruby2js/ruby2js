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
    it "generates createTable call" do
      result = to_js(<<~RUBY)
        ActiveRecord::Schema.define do
          create_table "articles" do |t|
            t.string "title"
          end
        end
      RUBY
      assert_includes result, 'createTable("articles"'
    end

    it "adds id primary key by default" do
      result = to_js(<<~RUBY)
        ActiveRecord::Schema.define do
          create_table "articles" do |t|
            t.string "title"
          end
        end
      RUBY
      assert_includes result, 'name: "id", type: "integer", primaryKey: true, autoIncrement: true'
    end
  end

  describe "column types" do
    it "uses abstract string type" do
      result = to_js(<<~RUBY)
        ActiveRecord::Schema.define do
          create_table "articles" do |t|
            t.string "title"
          end
        end
      RUBY
      assert_includes result, 'name: "title", type: "string"'
    end

    it "uses abstract text type" do
      result = to_js(<<~RUBY)
        ActiveRecord::Schema.define do
          create_table "articles" do |t|
            t.text "body"
          end
        end
      RUBY
      assert_includes result, 'name: "body", type: "text"'
    end

    it "uses abstract integer type" do
      result = to_js(<<~RUBY)
        ActiveRecord::Schema.define do
          create_table "articles" do |t|
            t.integer "count"
          end
        end
      RUBY
      assert_includes result, 'name: "count", type: "integer"'
    end

    it "uses abstract boolean type" do
      result = to_js(<<~RUBY)
        ActiveRecord::Schema.define do
          create_table "articles" do |t|
            t.boolean "published"
          end
        end
      RUBY
      assert_includes result, 'name: "published", type: "boolean"'
    end

    it "uses abstract datetime type" do
      result = to_js(<<~RUBY)
        ActiveRecord::Schema.define do
          create_table "articles" do |t|
            t.datetime "published_at"
          end
        end
      RUBY
      assert_includes result, 'name: "published_at", type: "datetime"'
    end

    it "uses abstract float type" do
      result = to_js(<<~RUBY)
        ActiveRecord::Schema.define do
          create_table "articles" do |t|
            t.float "rating"
          end
        end
      RUBY
      assert_includes result, 'name: "rating", type: "float"'
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
      assert_includes result, 'name: "title", type: "string", null: false'
    end

    it "handles default string value" do
      result = to_js(<<~RUBY)
        ActiveRecord::Schema.define do
          create_table "articles" do |t|
            t.string "status", default: "draft"
          end
        end
      RUBY
      assert_includes result, 'default: "draft"'
    end

    it "handles default integer value" do
      result = to_js(<<~RUBY)
        ActiveRecord::Schema.define do
          create_table "articles" do |t|
            t.integer "count", default: 0
          end
        end
      RUBY
      assert_includes result, 'default: 0'
    end

    it "handles default boolean value" do
      result = to_js(<<~RUBY)
        ActiveRecord::Schema.define do
          create_table "articles" do |t|
            t.boolean "published", default: false
          end
        end
      RUBY
      assert_includes result, 'default: false'
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
      assert_includes result, 'name: "created_at", type: "datetime"'
      assert_includes result, 'name: "updated_at", type: "datetime"'
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
      assert_includes result, 'name: "article_id", type: "integer"'
    end

    it "adds null: false by default" do
      result = to_js(<<~RUBY)
        ActiveRecord::Schema.define do
          create_table "comments" do |t|
            t.references "article"
          end
        end
      RUBY
      assert_includes result, 'name: "article_id", type: "integer", null: false'
    end

    it "adds foreign key constraint when specified" do
      result = to_js(<<~RUBY)
        ActiveRecord::Schema.define do
          create_table "comments" do |t|
            t.references "article", foreign_key: true
          end
        end
      RUBY
      assert_includes result, 'foreignKeys'
      assert_includes result, 'column: "article_id"'
      assert_includes result, 'references: "articles"'
    end
  end

  describe "add_index" do
    it "creates addIndex call on single column" do
      result = to_js(<<~RUBY)
        ActiveRecord::Schema.define do
          create_table "articles" do |t|
            t.string "title"
          end
          add_index "articles", ["title"]
        end
      RUBY
      assert_includes result, 'addIndex("articles", ["title"]'
    end

    it "creates addIndex call on multiple columns" do
      result = to_js(<<~RUBY)
        ActiveRecord::Schema.define do
          create_table "articles" do |t|
            t.string "status"
            t.datetime "created_at"
          end
          add_index "articles", ["status", "created_at"]
        end
      RUBY
      assert_includes result, 'addIndex'
      assert_includes result, '"status", "created_at"'
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
      assert_includes result, 'unique: true'
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

    it "imports createTable and addIndex from adapter" do
      result = to_js(<<~RUBY)
        ActiveRecord::Schema.define do
          create_table "articles" do |t|
            t.string "title"
          end
        end
      RUBY
      assert_includes result, 'import { createTable, addIndex } from "../lib/active_record.mjs"'
      assert_includes result, 'createTable('
    end
  end
end
