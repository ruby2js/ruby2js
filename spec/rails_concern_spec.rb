require 'minitest/autorun'
require 'ruby2js/filter/rails/concern'
require 'ruby2js/filter/esm'

describe Ruby2JS::Filter::Rails::Concern do
  def to_js(string, options = {})
    Ruby2JS.convert(string, {
      filters: [Ruby2JS::Filter::Rails::Concern, Ruby2JS::Filter::ESM],
      eslevel: 2020
    }.merge(options)).to_s
  end

  describe "detection" do
    it "detects extend ActiveSupport::Concern" do
      result = to_js(<<~RUBY)
        module Foo
          extend ActiveSupport::Concern
          def bar; end
        end
      RUBY
      # Should produce IIFE (concern forces it), not object literal
      assert_includes result, '(() => {'
      assert_includes result, 'function bar()'
    end

    it "does not affect modules without extend ActiveSupport::Concern" do
      result = to_js(<<~RUBY)
        module Foo
          def bar; end
        end
      RUBY
      # Without concern, simple path produces object literal
      refute_includes result, '(() => {'
    end
  end

  describe "stripping" do
    it "strips extend ActiveSupport::Concern" do
      result = to_js(<<~RUBY)
        module Foo
          extend ActiveSupport::Concern
          def bar; end
        end
      RUBY
      refute_includes result, 'extend'
      refute_includes result, 'ActiveSupport'
    end

    it "strips included do...end block" do
      result = to_js(<<~RUBY)
        module Foo
          extend ActiveSupport::Concern
          included do
            has_many :bars
            before_save :check
          end
          def baz; end
        end
      RUBY
      refute_includes result, 'has_many'
      refute_includes result, 'before_save'
      refute_includes result, 'included'
      assert_includes result, 'function baz()'
    end

    it "strips class_methods do...end block" do
      result = to_js(<<~RUBY)
        module Foo
          extend ActiveSupport::Concern
          class_methods do
            def find_by_key(key)
              key
            end
          end
          def bar; end
        end
      RUBY
      refute_includes result, 'find_by_key'
      refute_includes result, 'class_methods'
      assert_includes result, 'function bar()'
    end

    it "strips delegate calls" do
      result = to_js(<<~RUBY)
        module Foo
          extend ActiveSupport::Concern
          delegate :name, to: :user
          def bar; end
        end
      RUBY
      refute_includes result, 'delegate'
      assert_includes result, 'function bar()'
    end

    it "strips include calls" do
      result = to_js(<<~RUBY)
        module Foo
          extend ActiveSupport::Concern
          include ActionView::Helpers::TagHelper
          def bar; end
        end
      RUBY
      refute_includes result, 'include'
      refute_includes result, 'ActionView'
      assert_includes result, 'function bar()'
    end
  end

  describe "attr_accessor transformation" do
    it "transforms attr_accessor to getter/setter" do
      result = to_js(<<~RUBY)
        module Foo
          extend ActiveSupport::Concern
          attr_accessor :bar
        end
      RUBY
      assert_includes result, 'get bar()'
      assert_includes result, 'set bar(val)'
      assert_includes result, 'return this._bar'
      assert_includes result, 'this._bar = val'
    end

    it "transforms multiple attr_accessor names" do
      result = to_js(<<~RUBY)
        module Foo
          extend ActiveSupport::Concern
          attr_accessor :bar, :baz
        end
      RUBY
      assert_includes result, 'get bar()'
      assert_includes result, 'set bar(val)'
      assert_includes result, 'get baz()'
      assert_includes result, 'set baz(val)'
    end

    it "transforms attr_reader to a reader function" do
      result = to_js(<<~RUBY)
        module Foo
          extend ActiveSupport::Concern
          attr_reader :bar
          def baz; end
        end
      RUBY
      # Without a matching setter, the module converter treats this as a
      # regular function (getter/setter pair detection requires def x=)
      assert_includes result, 'function bar()'
      assert_includes result, 'this._bar'
      refute_includes result, 'set bar('
    end

    it "transforms attr_writer to setter accessor" do
      result = to_js(<<~RUBY)
        module Foo
          extend ActiveSupport::Concern
          attr_writer :bar
          def baz; end
        end
      RUBY
      # The module converter detects def bar= as a setter and produces set accessor
      assert_includes result, 'set bar(val)'
      assert_includes result, 'this._bar = val'
      refute_includes result, 'get bar()'
    end
  end

  describe "alias_method transformation" do
    it "creates delegating def for different base names" do
      result = to_js(<<~RUBY)
        module Foo
          extend ActiveSupport::Concern
          def published?
            true
          end
          alias_method :publicly_accessible?, :published?
        end
      RUBY
      assert_includes result, 'publicly_accessible'
      assert_includes result, 'published()'
    end

    it "strips alias_method when names differ only by ? suffix" do
      result = to_js(<<~RUBY)
        module Foo
          extend ActiveSupport::Concern
          attr_accessor :was_just_published
          alias_method :was_just_published?, :was_just_published
          def bar; end
        end
      RUBY
      # The alias should be stripped since was_just_published? and
      # was_just_published have the same base name
      refute_match(/alias/, result)
      # But the accessor should still exist
      assert_includes result, 'get was_just_published()'
      assert_includes result, 'set was_just_published(val)'
    end
  end

  describe "visibility markers" do
    it "keeps private marker and hides private methods" do
      result = to_js(<<~RUBY)
        module Foo
          extend ActiveSupport::Concern
          def bar; end
          private
          def check; end
        end
      RUBY
      assert_includes result, 'function bar()'
      assert_includes result, 'function check()'
      # bar should be in return object, check should not
      assert_match(/return \{bar\}/, result)
    end
  end

  describe "IIFE path" do
    it "uses underscored private fields (not # fields)" do
      result = to_js(<<~RUBY)
        module Foo
          extend ActiveSupport::Concern
          def bar
            @boards
          end
        end
      RUBY
      assert_includes result, 'this._boards'
      refute_includes result, 'this.#boards'
    end
  end

  describe "namespaced modules" do
    it "handles Card::Statuses namespace" do
      result = to_js(<<~RUBY)
        module Card::Statuses
          extend ActiveSupport::Concern
          attr_accessor :was_just_published
          def publish; end
        end
      RUBY
      assert_includes result, 'get was_just_published()'
      assert_includes result, 'set was_just_published(val)'
      assert_includes result, 'publish'
    end
  end
end
