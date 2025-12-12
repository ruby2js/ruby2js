require 'minitest/autorun'
require 'ruby2js/filter/alpine'
require 'ruby2js/filter/esm'
require 'ruby2js/filter/functions'

describe Ruby2JS::Filter::Alpine do

  def to_js(string)
    _(Ruby2JS.convert(string, eslevel: 2022,
      filters: [Ruby2JS::Filter::Alpine]).to_s)
  end

  def to_js_esm(string)
    _(Ruby2JS.convert(string, eslevel: 2022,
      filters: [Ruby2JS::Filter::Alpine, Ruby2JS::Filter::ESM]).to_s)
  end

  def to_js_fn(string)
    _(Ruby2JS.convert(string, eslevel: 2022,
      filters: [Ruby2JS::Filter::Alpine, Ruby2JS::Filter::Functions]).to_s)
  end

  describe "Alpine.data" do
    it "should create basic component" do
      result = to_js('Alpine.data :counter do; @count = 0; end')
      result.must_include 'Alpine.data("counter"'
      result.must_include 'count: 0'
    end

    it "should handle initialize method" do
      result = to_js('Alpine.data :counter do; def initialize; @count = 0; end; end')
      result.must_include 'count: 0'
    end

    it "should create methods" do
      result = to_js('Alpine.data :counter do; def increment; @count += 1; end; end')
      result.must_include 'increment()'
      result.must_include 'this.count'
    end

    it "should handle instance variable reads" do
      result = to_js('Alpine.data :display do; def show; console.log @message; end; end')
      result.must_include 'this.message'
    end

    it "should handle complete component" do
      code = <<~RUBY
        Alpine.data :counter do
          def initialize
            @count = 0
          end

          def increment
            @count += 1
          end

          def decrement
            @count -= 1
          end
        end
      RUBY
      result = to_js(code)
      result.must_include 'Alpine.data'
      result.must_include '"counter"'
      result.must_include 'count: 0'
      result.must_include 'increment()'
      result.must_include 'decrement()'
    end
  end

  describe "magic properties" do
    it "should convert _el to this.$el" do
      result = to_js('Alpine.data :test do; def click; _el.focus(); end; end')
      result.must_include 'this.$el.focus()'
    end

    it "should convert _refs to this.$refs" do
      result = to_js('Alpine.data :test do; def focus; _refs.input.focus(); end; end')
      result.must_include 'this.$refs.input'
    end

    it "should convert _dispatch to this.$dispatch" do
      result = to_js('Alpine.data :test do; def notify; _dispatch "custom-event"; end; end')
      result.must_include 'this.$dispatch("custom-event")'
    end

    it "should convert _nextTick to this.$nextTick" do
      result = to_js('Alpine.data :test do; def update; _nextTick { focus() }; end; end')
      result.must_include 'this.$nextTick'
    end
  end

  describe "esm imports" do
    it "should import Alpine when ESM is enabled" do
      result = to_js_esm('Alpine.data :test do; @x = 1; end')
      result.must_include 'import Alpine from "alpinejs"'
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include Alpine" do
      _(Ruby2JS::Filter::DEFAULTS).must_include Ruby2JS::Filter::Alpine
    end
  end
end
