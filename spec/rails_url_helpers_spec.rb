require 'minitest/autorun'
require 'ruby2js/filter/rails/model'
require 'ruby2js/filter/esm'

describe "Rails url_helpers transpilation" do
  def to_js(string, options = {})
    Ruby2JS.convert(string, {
      filters: [Ruby2JS::Filter::Rails::Model, Ruby2JS::Filter::ESM],
      eslevel: 2020
    }.merge(options)).to_s
  end

  describe "include Rails.application.routes.url_helpers" do
    it "strips the include from class body" do
      result = to_js(<<~RUBY)
        class Delivery < ApplicationRecord
          include Rails.application.routes.url_helpers
        end
      RUBY
      refute_includes result, 'Object.defineProperties'
      refute_includes result, 'url_helpers'
      refute_includes result, 'include'
    end

    it "generates import for polymorphic_url and polymorphic_path" do
      result = to_js(<<~RUBY)
        class Delivery < ApplicationRecord
          include Rails.application.routes.url_helpers
        end
      RUBY
      assert_includes result, 'polymorphic_url, polymorphic_path'
      assert_includes result, 'from "juntos:url-helpers"'
    end

    it "preserves other class body content" do
      result = to_js(<<~RUBY)
        class Delivery < ApplicationRecord
          include Rails.application.routes.url_helpers

          def deliver
            save
          end
        end
      RUBY
      assert_includes result, 'deliver'
      refute_includes result, 'url_helpers'
    end
  end

  describe "class without url_helpers" do
    it "does not generate url_helpers import" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          has_many :comments
        end
      RUBY
      refute_includes result, 'polymorphic_url'
      refute_includes result, 'polymorphic_path'
      refute_includes result, 'juntos:url-helpers'
    end
  end

  describe "other includes are not affected" do
    it "passes through non-url_helpers includes" do
      result = to_js(<<~RUBY)
        class Article < ApplicationRecord
          has_many :comments
        end
      RUBY
      # No includes at all, so nothing should be stripped
      refute_includes result, 'include'
    end
  end

  describe "non-model class with url_helpers" do
    it "strips the include and adds import for plain classes" do
      result = to_js(<<~RUBY)
        class NotificationPusher
          include Rails.application.routes.url_helpers

          def push
            url = polymorphic_url(record)
          end
        end
      RUBY
      assert_includes result, 'polymorphic_url, polymorphic_path'
      assert_includes result, 'from "juntos:url-helpers"'
      assert_includes result, 'class NotificationPusher'
      assert_includes result, 'push()'
      refute_includes result, 'Object.defineProperties'
      refute_includes result, 'url_helpers'
    end

    it "preserves other includes in non-model classes" do
      result = to_js(<<~RUBY)
        class NotificationPusher
          include Rails.application.routes.url_helpers
          include ExcerptHelper
        end
      RUBY
      assert_includes result, 'polymorphic_url, polymorphic_path'
      assert_includes result, 'ExcerptHelper'
      refute_includes result, 'url_helpers'
    end
  end

  describe "multiple features with url_helpers" do
    it "works alongside associations and validations" do
      result = to_js(<<~RUBY)
        class Delivery < ApplicationRecord
          include Rails.application.routes.url_helpers
          belongs_to :event
          validates :url, presence: true
        end
      RUBY
      assert_includes result, 'polymorphic_url, polymorphic_path'
      assert_includes result, 'from "juntos:url-helpers"'
      assert_includes result, 'event()'  # association method
      assert_includes result, 'validates_presence_of' # validation
      refute_includes result, 'Object.defineProperties'
    end
  end
end
