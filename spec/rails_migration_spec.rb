require 'minitest/autorun'
require 'ruby2js/filter/rails/migration'
require 'ruby2js/filter/esm'

describe Ruby2JS::Filter::Rails::Migration do
  def to_js(string, options = {})
    Ruby2JS.convert(string, {
      filters: [Ruby2JS::Filter::Rails::Migration, Ruby2JS::Filter::ESM],
      eslevel: 2020
    }.merge(options)).to_s
  end

  describe "detection" do
    it "detects class extending ActiveRecord::Migration" do
      result = to_js(<<~RUBY)
        class CreateArticles < ActiveRecord::Migration[7.1]
          def change
            create_table :articles do |t|
              t.string :title
              t.timestamps
            end
          end
        end
      RUBY
      assert_includes result, 'export const migration'
      assert_includes result, 'up:'
    end

    it "does not affect other classes" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          has_many :comments
        end
      RUBY
      refute_includes result, 'export const migration'
      refute_includes result, 'createTable'
    end
  end

  describe "adapter parameter" do
    it "receives adapter as parameter instead of importing DDL functions" do
      result = to_js(<<~RUBY)
        class CreateArticles < ActiveRecord::Migration[7.1]
          def change
            create_table :articles do |t|
              t.string :title
            end
          end
        end
      RUBY
      # Migrations receive adapter as parameter, no imports needed
      assert_includes result, 'up: async adapter =>'
      refute_includes result, 'import { createTable'
    end
  end

  describe "create_table" do
    it "generates createTable call with columns" do
      result = to_js(<<~RUBY)
        class CreateArticles < ActiveRecord::Migration[7.1]
          def change
            create_table :articles do |t|
              t.string :title
              t.text :body
            end
          end
        end
      RUBY
      assert_includes result, 'await adapter.createTable("articles"'
      assert_includes result, 'name: "id"'
      assert_includes result, 'name: "title"'
      assert_includes result, 'type: "string"'
      assert_includes result, 'name: "body"'
      assert_includes result, 'type: "text"'
    end

    it "adds primary key column by default" do
      result = to_js(<<~RUBY)
        class CreateArticles < ActiveRecord::Migration[7.1]
          def change
            create_table :articles do |t|
              t.string :title
            end
          end
        end
      RUBY
      assert_includes result, 'primaryKey: true'
      assert_includes result, 'autoIncrement: true'
    end

    it "handles timestamps" do
      result = to_js(<<~RUBY)
        class CreateArticles < ActiveRecord::Migration[7.1]
          def change
            create_table :articles do |t|
              t.string :title
              t.timestamps
            end
          end
        end
      RUBY
      assert_includes result, 'name: "created_at"'
      assert_includes result, 'name: "updated_at"'
      assert_includes result, 'type: "datetime"'
    end

    it "handles null: false option" do
      result = to_js(<<~RUBY)
        class CreateArticles < ActiveRecord::Migration[7.1]
          def change
            create_table :articles do |t|
              t.string :title, null: false
            end
          end
        end
      RUBY
      assert_includes result, 'null: false'
    end

    it "handles default values" do
      result = to_js(<<~RUBY)
        class CreateArticles < ActiveRecord::Migration[7.1]
          def change
            create_table :articles do |t|
              t.string :status, default: "draft"
              t.integer :views, default: 0
              t.boolean :published, default: false
            end
          end
        end
      RUBY
      assert_includes result, 'default: "draft"'
      assert_includes result, 'default: 0'
      assert_includes result, 'default: false'
    end

    it "handles various column types" do
      result = to_js(<<~RUBY)
        class CreateArticles < ActiveRecord::Migration[7.1]
          def change
            create_table :articles do |t|
              t.string :title
              t.text :body
              t.integer :views
              t.float :rating
              t.boolean :published
              t.date :publish_date
              t.datetime :expires_at
              t.json :metadata
            end
          end
        end
      RUBY
      assert_includes result, 'type: "string"'
      assert_includes result, 'type: "text"'
      assert_includes result, 'type: "integer"'
      assert_includes result, 'type: "float"'
      assert_includes result, 'type: "boolean"'
      assert_includes result, 'type: "date"'
      assert_includes result, 'type: "datetime"'
      assert_includes result, 'type: "json"'
    end
  end

  describe "references" do
    it "creates foreign key column" do
      result = to_js(<<~RUBY)
        class CreateComments < ActiveRecord::Migration[7.1]
          def change
            create_table :comments do |t|
              t.references :article, null: false, foreign_key: true
              t.text :body
            end
          end
        end
      RUBY
      assert_includes result, 'name: "article_id"'
      assert_includes result, 'type: "integer"'
      assert_includes result, 'foreignKeys'
      assert_includes result, 'references: "articles"'
    end

    it "handles belongs_to" do
      result = to_js(<<~RUBY)
        class CreateComments < ActiveRecord::Migration[7.1]
          def change
            create_table :comments do |t|
              t.belongs_to :article, foreign_key: true
              t.text :body
            end
          end
        end
      RUBY
      assert_includes result, 'name: "article_id"'
    end
  end

  describe "add_index" do
    it "generates addIndex call" do
      result = to_js(<<~RUBY)
        class AddIndexToArticles < ActiveRecord::Migration[7.1]
          def change
            add_index :articles, :status
          end
        end
      RUBY
      assert_includes result, 'await adapter.addIndex("articles", ["status"])'
    end

    it "handles multi-column index" do
      result = to_js(<<~RUBY)
        class AddIndexToArticles < ActiveRecord::Migration[7.1]
          def change
            add_index :articles, [:user_id, :created_at]
          end
        end
      RUBY
      assert_includes result, '["user_id", "created_at"]'
    end

    it "handles unique index" do
      result = to_js(<<~RUBY)
        class AddIndexToUsers < ActiveRecord::Migration[7.1]
          def change
            add_index :users, :email, unique: true
          end
        end
      RUBY
      assert_includes result, 'adapter.addIndex("users", ["email"]'
      assert_includes result, 'unique: true'
    end

    it "handles custom index name" do
      result = to_js(<<~RUBY)
        class AddIndexToArticles < ActiveRecord::Migration[7.1]
          def change
            add_index :articles, :slug, name: 'idx_articles_slug'
          end
        end
      RUBY
      assert_includes result, 'name: "idx_articles_slug"'
    end
  end

  describe "add_column" do
    it "generates addColumn call" do
      result = to_js(<<~RUBY)
        class AddSlugToArticles < ActiveRecord::Migration[7.1]
          def change
            add_column :articles, :slug, :string
          end
        end
      RUBY
      assert_includes result, 'await adapter.addColumn("articles", "slug", "string")'
    end
  end

  describe "remove_column" do
    it "generates removeColumn call" do
      result = to_js(<<~RUBY)
        class RemoveSlugFromArticles < ActiveRecord::Migration[7.1]
          def change
            remove_column :articles, :slug
          end
        end
      RUBY
      assert_includes result, 'await adapter.removeColumn("articles", "slug")'
    end
  end

  describe "drop_table" do
    it "generates dropTable call" do
      result = to_js(<<~RUBY)
        class DropOldArticles < ActiveRecord::Migration[7.1]
          def change
            drop_table :old_articles
          end
        end
      RUBY
      assert_includes result, 'await adapter.dropTable("old_articles")'
    end
  end

  describe "tableSchemas" do
    it "generates Dexie schema strings" do
      result = to_js(<<~RUBY)
        class CreateArticles < ActiveRecord::Migration[7.1]
          def change
            create_table :articles do |t|
              t.string :title
              t.text :body
              t.timestamps
            end
          end
        end
      RUBY
      assert_includes result, 'tableSchemas:'
      assert_includes result, 'articles: "++id, title, body, created_at, updated_at"'
    end

    it "includes multiple table schemas" do
      result = to_js(<<~RUBY)
        class CreateArticlesAndComments < ActiveRecord::Migration[7.1]
          def change
            create_table :articles do |t|
              t.string :title
            end
            create_table :comments do |t|
              t.text :body
            end
          end
        end
      RUBY
      # Should not contain tableSchemas for simple add_index migration
      # since no tables are created
      assert_includes result, 'tableSchemas'
    end

    it "does not include tableSchemas for non-create migrations" do
      result = to_js(<<~RUBY)
        class AddIndexToArticles < ActiveRecord::Migration[7.1]
          def change
            add_index :articles, :status
          end
        end
      RUBY
      refute_includes result, 'tableSchemas'
    end
  end

  describe "async export" do
    it "exports migration object with async up function" do
      result = to_js(<<~RUBY)
        class CreateArticles < ActiveRecord::Migration[7.1]
          def change
            create_table :articles do |t|
              t.string :title
            end
          end
        end
      RUBY
      assert_includes result, 'export const migration'
      assert_includes result, 'up: async adapter =>'
    end
  end

  describe "multiple statements" do
    it "handles multiple migration statements" do
      result = to_js(<<~RUBY)
        class CreateArticlesWithIndex < ActiveRecord::Migration[7.1]
          def change
            create_table :articles do |t|
              t.string :title
              t.string :status
              t.timestamps
            end
            add_index :articles, :status
          end
        end
      RUBY
      assert_includes result, 'await adapter.createTable("articles"'
      assert_includes result, 'await adapter.addIndex("articles", ["status"])'
    end
  end
end
