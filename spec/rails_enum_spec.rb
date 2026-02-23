require 'minitest/autorun'
require 'ruby2js/filter/rails/model'
require 'ruby2js/filter/esm'

describe "Rails enum transpilation" do
  def to_js(string, options = {})
    Ruby2JS.convert(string, {
      filters: [Ruby2JS::Filter::Rails::Model, Ruby2JS::Filter::ESM],
      eslevel: 2020
    }.merge(options)).to_s
  end

  describe "string enum (index_by)" do
    it "generates frozen values constant" do
      result = to_js(<<~RUBY)
        class Export < ApplicationRecord
          enum :status, %w[drafted published].index_by(&:itself)
        end
      RUBY
      assert_includes result, 'Object.freeze('
      assert_includes result, 'drafted: "drafted"'
      assert_includes result, 'published: "published"'
      assert_includes result, 'Export.statuses'
    end

    it "generates instance predicate methods" do
      result = to_js(<<~RUBY)
        class Export < ApplicationRecord
          enum :status, %w[drafted published].index_by(&:itself)
        end
      RUBY
      assert_includes result, 'drafted() {'
      assert_includes result, 'return this.status === "drafted"'
      assert_includes result, 'published() {'
      assert_includes result, 'return this.status === "published"'
    end

    it "generates static scope methods" do
      result = to_js(<<~RUBY)
        class Export < ApplicationRecord
          enum :status, %w[drafted published].index_by(&:itself)
        end
      RUBY
      assert_includes result, 'static get drafted() {'
      assert_includes result, 'return this.where({status: "drafted"})'
      assert_includes result, 'static get published() {'
      assert_includes result, 'return this.where({status: "published"})'
    end
  end

  describe "symbol array with index_by" do
    it "generates string values for %i[...].index_by(&:itself)" do
      result = to_js(<<~RUBY)
        class Access < ApplicationRecord
          enum :involvement, %i[access_only watching].index_by(&:itself)
        end
      RUBY
      assert_includes result, 'this.involvement === "access_only"'
      assert_includes result, 'access_only: "access_only"'
      assert_includes result, 'watching: "watching"'
    end
  end

  describe "integer enum (bare array)" do
    it "generates integer comparisons for %i[...] array" do
      result = to_js(<<~RUBY)
        class NotificationBundle < ApplicationRecord
          enum :status, %i[pending processing delivered]
        end
      RUBY
      assert_includes result, 'this.status === 0'
      assert_includes result, 'this.status === 1'
      assert_includes result, 'this.status === 2'
    end

    it "generates integer comparisons for %w[...] array" do
      result = to_js(<<~RUBY)
        class MagicLink < ApplicationRecord
          enum :purpose, %w[sign_in sign_up]
        end
      RUBY
      assert_includes result, 'this.purpose === 0'
      assert_includes result, 'this.purpose === 1'
      assert_includes result, 'Object.freeze({sign_in: 0, sign_up: 1})'
    end

    it "generates integer where clauses in scopes" do
      result = to_js(<<~RUBY)
        class NotificationBundle < ApplicationRecord
          enum :status, %i[pending processing delivered]
        end
      RUBY
      assert_includes result, 'return this.where({status: 0})'
      assert_includes result, 'return this.where({status: 2})'
    end
  end

  describe "prefix option" do
    it "prepends custom prefix to method names" do
      result = to_js(<<~RUBY)
        class MagicLink < ApplicationRecord
          enum :purpose, %w[sign_in sign_up], prefix: :for
        end
      RUBY
      assert_includes result, 'for_sign_in() {'
      assert_includes result, 'static get for_sign_in() {'
      assert_includes result, 'for_sign_up() {'
      assert_includes result, 'static get for_sign_up() {'
      # Should not generate unprefixed methods
      refute_match(/[^_]sign_in\(\)/, result)
    end

    it "uses field name as prefix when prefix: true" do
      result = to_js(<<~RUBY)
        class Export < ApplicationRecord
          enum :status, %w[drafted published].index_by(&:itself), prefix: true
        end
      RUBY
      assert_includes result, 'status_drafted() {'
      assert_includes result, 'status_published() {'
    end
  end

  describe "scopes: false option" do
    it "skips scope generation" do
      result = to_js(<<~RUBY)
        class User < ApplicationRecord
          enum :role, %i[owner admin].index_by(&:itself), scopes: false
        end
      RUBY
      # Instance predicates should still be generated
      assert_includes result, 'owner() {'
      assert_includes result, 'return this.role === "owner"'
      # Static scopes should NOT be generated
      refute_includes result, 'static owner() {'
      refute_includes result, 'static admin() {'
    end
  end

  describe "inline predicate transform" do
    it "inlines ? calls to comparison within class body" do
      result = to_js(<<~RUBY)
        class Export < ApplicationRecord
          enum :status, %w[drafted published].index_by(&:itself)

          def visible?
            published?
          end
        end
      RUBY
      assert_includes result, 'this.status === "published"'
    end

    it "inlines prefixed ? calls" do
      result = to_js(<<~RUBY)
        class MagicLink < ApplicationRecord
          enum :purpose, %w[sign_in sign_up], prefix: :for

          def login?
            for_sign_in?
          end
        end
      RUBY
      assert_includes result, 'this.purpose === 0'
    end
  end

  describe "inline mutator transform" do
    it "inlines ! calls to update within class body" do
      result = to_js(<<~RUBY)
        class Export < ApplicationRecord
          enum :status, %w[drafted published].index_by(&:itself)

          def finish
            published!
          end
        end
      RUBY
      assert_includes result, 'this.update({status: "published"})'
    end
  end

  describe "explicit method override" do
    it "does not clobber explicitly defined methods" do
      result = to_js(<<~RUBY)
        class Export < ApplicationRecord
          enum :status, %w[drafted published].index_by(&:itself)

          def published?
            status == "published" && visible
          end
        end
      RUBY
      # Should still generate drafted predicate (as getter in model context)
      assert_includes result, 'get drafted() {'
      assert_includes result, 'return this.status === "drafted"'
      # Should NOT generate published predicate (user defined it)
      occurrences = result.scan(/^\s*get published\(\)/).length
      assert_equal 1, occurrences, "get published() should appear exactly once (user-defined)"
    end
  end

  describe "multiple enums" do
    it "generates methods for all enums in a class" do
      result = to_js(<<~RUBY)
        class Order < ApplicationRecord
          enum :status, %w[pending shipped].index_by(&:itself)
          enum :priority, %i[low high]
        end
      RUBY
      # Status methods
      assert_includes result, 'return this.status === "pending"'
      assert_includes result, 'return this.where({status: "shipped"})'
      # Priority methods
      assert_includes result, 'return this.priority === 0'
      assert_includes result, 'return this.where({priority: 1})'
      # Both frozen constants
      assert_includes result, 'Order.statuses = Object.freeze'
      assert_includes result, 'Order.priorities = Object.freeze'
    end
  end

  describe "enum declaration removal" do
    it "removes enum declaration from class body" do
      result = to_js(<<~RUBY)
        class Export < ApplicationRecord
          enum :status, %w[drafted published].index_by(&:itself), default: :pending
        end
      RUBY
      refute_includes result, 'enum('
      refute_includes result, 'index_by'
    end
  end
end
