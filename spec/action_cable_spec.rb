require 'minitest/autorun'
require 'ruby2js/filter/action_cable'
require 'ruby2js/filter/esm'

describe Ruby2JS::Filter::ActionCable do

  def to_js(string)
    _(Ruby2JS.convert(string, eslevel: 2022,
      filters: [Ruby2JS::Filter::ActionCable]).to_s)
  end

  def to_js_esm(string)
    _(Ruby2JS.convert(string, eslevel: 2022,
      filters: [Ruby2JS::Filter::ActionCable, Ruby2JS::Filter::ESM]).to_s)
  end

  describe "createConsumer" do
    it "should convert ActionCable.createConsumer()" do
      result = to_js('consumer = ActionCable.createConsumer()')
      result.must_include 'createConsumer()'
    end

    it "should convert ActionCable.createConsumer(url)" do
      result = to_js('consumer = ActionCable.createConsumer("/cable")')
      result.must_include 'createConsumer("/cable")'
    end
  end

  describe "subscriptions.create" do
    it "should convert basic subscription" do
      code = <<~RUBY
        consumer.subscriptions.create "ChatChannel",
          received: ->(data) { handle(data) }
      RUBY
      result = to_js(code)
      result.must_include 'consumer.subscriptions.create'
      result.must_include '"ChatChannel"'
      result.must_include 'received(data)'
    end

    it "should convert connected callback" do
      code = <<~RUBY
        consumer.subscriptions.create "ChatChannel",
          connected: -> { console.log("Connected") }
      RUBY
      result = to_js(code)
      result.must_include 'connected()'
      result.must_include 'console.log("Connected")'
    end

    it "should convert disconnected callback" do
      code = <<~RUBY
        consumer.subscriptions.create "ChatChannel",
          disconnected: -> { console.log("Disconnected") }
      RUBY
      result = to_js(code)
      result.must_include 'disconnected()'
    end

    it "should handle multiple callbacks" do
      code = <<~RUBY
        consumer.subscriptions.create "ChatChannel",
          connected: -> { setup() },
          received: ->(data) { handle(data) },
          disconnected: -> { cleanup() }
      RUBY
      result = to_js(code)
      result.must_include 'connected()'
      result.must_include 'received(data)'
      result.must_include 'disconnected()'
    end
  end

  describe "ESM imports" do
    it "should import createConsumer when ESM is enabled" do
      result = to_js_esm('consumer = ActionCable.createConsumer()')
      result.must_include 'import { createConsumer } from "@rails/actioncable"'
    end
  end

  describe Ruby2JS::Filter::DEFAULTS do
    it "should include ActionCable" do
      _(Ruby2JS::Filter::DEFAULTS).must_include Ruby2JS::Filter::ActionCable
    end
  end
end
