require 'minitest/autorun'
require 'ruby2js/filter/rails/concern'
require 'ruby2js/filter/rails/model'
require 'ruby2js/filter/esm'

describe Ruby2JS::Filter::Rails::Concern do
  def to_js(string, options = {})
    Ruby2JS.convert(string, {
      filters: [Ruby2JS::Filter::Rails::Concern, Ruby2JS::Filter::Rails::Model, Ruby2JS::Filter::ESM],
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
      # Should produce factory function pattern
      assert_includes result, 'const Foo = (Base) => class extends Base {'
      assert_includes result, 'bar()'
    end

    it "does not affect modules without extend ActiveSupport::Concern" do
      result = to_js(<<~RUBY)
        module Foo
          def bar; end
        end
      RUBY
      # Without concern, module produces IIFE or object literal
      refute_includes result, '(Base) =>'
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
      refute_includes result, 'ActiveSupport'
    end

    it "strips included do...end DSL into class body" do
      result = to_js(<<~RUBY)
        module Foo
          extend ActiveSupport::Concern
          included do
            has_many :bars
          end
          def baz; end
        end
      RUBY
      # has_many is processed by model filter into association methods
      refute_includes result, 'included'
      assert_includes result, 'baz()'
      # Association getter should be generated
      assert_includes result, 'get bars()'
    end

    it "converts class_methods to static methods" do
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
      # class_methods become static methods in the factory class
      assert_includes result, 'static find_by_key(key)'
      assert_includes result, 'bar()'
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
      assert_includes result, 'bar()'
    end

    it "strips framework include calls" do
      result = to_js(<<~RUBY)
        module Foo
          extend ActiveSupport::Concern
          include ActionView::Helpers::TagHelper
          def bar; end
        end
      RUBY
      # Framework modules (nested consts) are stripped
      refute_includes result, 'ActionView'
      refute_includes result, 'TagHelper'
      assert_includes result, 'bar()'
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
      assert_includes result, 'set bar('
      assert_includes result, 'this._bar'
    end

    it "transforms multiple attr_accessor names" do
      result = to_js(<<~RUBY)
        module Foo
          extend ActiveSupport::Concern
          attr_accessor :bar, :baz
        end
      RUBY
      assert_includes result, 'get bar()'
      assert_includes result, 'set bar('
      assert_includes result, 'get baz()'
      assert_includes result, 'set baz('
    end

    it "transforms attr_reader to getter" do
      result = to_js(<<~RUBY)
        module Foo
          extend ActiveSupport::Concern
          attr_reader :bar
          def baz; end
        end
      RUBY
      assert_includes result, 'get bar()'
      assert_includes result, 'this._bar'
      refute_includes result, 'set bar('
    end

    it "transforms attr_writer to setter" do
      result = to_js(<<~RUBY)
        module Foo
          extend ActiveSupport::Concern
          attr_writer :bar
          def baz; end
        end
      RUBY
      assert_includes result, 'set bar('
      assert_includes result, 'this._bar'
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
      assert_includes result, 'set was_just_published('
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
      assert_includes result, 'bar()'
      # Private methods should use _ prefix (underscored_private is forced)
      assert_includes result, '_check()'
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

  describe "factory pattern" do
    it "generates factory function for concerns" do
      result = to_js(<<~RUBY)
        module Trackable
          extend ActiveSupport::Concern
          def track!
            update(tracked: true)
          end
        end
      RUBY
      assert_includes result, 'const Trackable = (Base) => class extends Base {'
    end

    it "handles concern including another concern" do
      result = to_js(<<~RUBY)
        module Foo
          extend ActiveSupport::Concern
          include Bar
          def baz; end
        end
      RUBY
      # include Bar → extends Bar(Base)
      assert_includes result, 'extends Bar(Base)'
      assert_includes result, 'import { Bar }'
    end

    it "handles multiple concern includes" do
      result = to_js(<<~RUBY)
        module Foo
          extend ActiveSupport::Concern
          include A
          include B
          def baz; end
        end
      RUBY
      # include A; include B → extends B(A(Base))
      assert_includes result, 'extends B(A(Base))'
    end

    it "generates static associations with spread" do
      result = to_js(<<~RUBY)
        module Trackable
          extend ActiveSupport::Concern
          included do
            has_many :tracks
          end
        end
      RUBY
      assert_includes result, '...super.associations'
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
      assert_includes result, 'set was_just_published('
      assert_includes result, 'publish()'
    end
  end

  describe "loop do in concerns" do
    it "should preserve loop do as while(true) with break" do
      result = to_js(<<~RUBY)
        module Cleanup
          extend ActiveSupport::Concern
          def cleanup(items)
            loop do
              item = items.find { |i| i[:stale] }
              break unless item
              items.delete(item)
            end
          end
        end
      RUBY
      assert_includes result, 'while (true)'
      assert_includes result, 'break'
    end
  end
end
