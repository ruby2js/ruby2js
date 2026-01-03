require 'minitest/autorun'
require 'ruby2js/filter/turbo'
require 'ruby2js/filter/esm'
require 'ruby2js/filter/functions'

describe Ruby2JS::Filter::Turbo do

  def to_js(string)
    _(Ruby2JS.convert(string, eslevel: 2022,
      filters: [Ruby2JS::Filter::Turbo]).to_s)
  end

  def to_js_esm(string)
    _(Ruby2JS.convert(string, eslevel: 2022,
      filters: [Ruby2JS::Filter::Turbo, Ruby2JS::Filter::ESM]).to_s)
  end

  def to_js_fn(string)
    _(Ruby2JS.convert(string, eslevel: 2022,
      filters: [Ruby2JS::Filter::Turbo, Ruby2JS::Filter::Functions]).to_s)
  end

  describe "stream_action" do
    it "should create custom stream action" do
      result = to_js('Turbo.stream_action :log do; console.log "test"; end')
      result.must_include 'Turbo.StreamActions.log ='
      result.must_include 'console.log("test")'
    end

    it "should prefix targetElements with this" do
      result = to_js_fn('Turbo.stream_action :highlight do; targetElements.each { |el| el.classList.add("highlight") }; end')
      result.must_include 'this.targetElements'
    end

    it "should prefix target with this" do
      result = to_js('Turbo.stream_action :remove do; target.remove(); end')
      result.must_include 'this.target'
    end

    it "should prefix templateContent with this" do
      result = to_js('Turbo.stream_action :append do; target.append(templateContent); end')
      result.must_include 'this.templateContent'
    end

    it "should handle getAttribute" do
      result = to_js('Turbo.stream_action :custom do; x = getAttribute("data-value"); end')
      result.must_include 'this.getAttribute("data-value")'
    end
  end

  describe "esm imports" do
    it "should import Turbo when ESM is enabled" do
      result = to_js_esm('Turbo.stream_action :log do; console.log target; end')
      result.must_include 'import Turbo from "@hotwired/turbo"'
    end
  end

  describe "turbo_frame_tag" do
    it "should generate turbo-frame with string id" do
      result = to_js('turbo_frame_tag "comments"')
      result.must_include 'turbo-frame'
      result.must_include 'id=\\"comments\\"'
    end

    it "should generate turbo-frame with symbol id" do
      result = to_js('turbo_frame_tag :comments')
      result.must_include 'turbo-frame'
      result.must_include 'id=\\"comments\\"'
    end

    it "should generate turbo-frame with src attribute" do
      result = to_js('turbo_frame_tag "edit", src: "/articles/1/edit"')
      result.must_include 'id=\\"edit\\"'
      result.must_include 'src=\\"/articles/1/edit\\"'
    end

    it "should generate turbo-frame with loading attribute" do
      result = to_js('turbo_frame_tag "comments", loading: :lazy')
      result.must_include 'id=\\"comments\\"'
      result.must_include 'loading=\\"lazy\\"'
    end

    it "should generate turbo-frame with target attribute" do
      result = to_js('turbo_frame_tag "nav", target: :_top')
      result.must_include 'id=\\"nav\\"'
      result.must_include 'target=\\"_top\\"'
    end

    it "should generate turbo-frame with multiple attributes" do
      result = to_js('turbo_frame_tag "edit", src: "/edit", loading: :lazy, target: :_top')
      result.must_include 'id=\\"edit\\"'
      result.must_include 'src=\\"/edit\\"'
      result.must_include 'loading=\\"lazy\\"'
      result.must_include 'target=\\"_top\\"'
    end

    it "should generate turbo-frame with block content" do
      result = to_js('turbo_frame_tag "comments" do; "content"; end')
      result.must_include '<turbo-frame'
      result.must_include '</turbo-frame>'
      result.must_include 'content'
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include Turbo" do
      _(Ruby2JS::Filter::DEFAULTS).must_include Ruby2JS::Filter::Turbo
    end
  end
end
