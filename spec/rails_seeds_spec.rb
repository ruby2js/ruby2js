require 'minitest/autorun'
require 'ruby2js/filter/rails/seeds'
require 'ruby2js/filter/esm'

describe Ruby2JS::Filter::Rails::Seeds do
  def to_js(string, options = {})
    Ruby2JS.convert(string, {
      filters: [Ruby2JS::Filter::Rails::Seeds, Ruby2JS::Filter::ESM],
      eslevel: 2020
    }.merge(options)).to_s
  end

  describe "detection" do
    it "detects module Seeds with def self.run" do
      result = to_js(<<~RUBY)
        module Seeds
          def self.run
            Article.create({title: "Test"})
          end
        end
      RUBY
      assert_includes result, 'export const Seeds'
      assert_includes result, 'function run()'
    end

    it "does not affect other modules" do
      result = to_js(<<~RUBY)
        module Other
          def self.run
            puts "hello"
          end
        end
      RUBY
      refute_includes result, 'import'
    end
  end

  describe "model detection" do
    it "auto-imports detected models" do
      result = to_js(<<~RUBY)
        module Seeds
          def self.run
            Article.create({title: "Test"})
          end
        end
      RUBY
      assert_includes result, 'import { Article } from "../app/models/index.js"'
    end

    it "imports multiple models" do
      result = to_js(<<~RUBY)
        module Seeds
          def self.run
            Article.create({title: "Test"})
            Comment.create({body: "Nice"})
            User.find(1)
          end
        end
      RUBY
      assert_includes result, 'Article'
      assert_includes result, 'Comment'
      assert_includes result, 'User'
      assert_includes result, '../app/models/index.js'
    end

    it "does not import Seeds itself" do
      result = to_js(<<~RUBY)
        module Seeds
          def self.run
            Seeds.helper
          end
        end
      RUBY
      refute_includes result, 'import { Seeds }'
    end
  end

  describe "export" do
    it "exports the Seeds module" do
      result = to_js(<<~RUBY)
        module Seeds
          def self.run
            Article.create({title: "Test"})
          end
        end
      RUBY
      assert_includes result, 'export const Seeds'
    end
  end
end
