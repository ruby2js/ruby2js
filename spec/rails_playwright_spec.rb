require 'minitest/autorun'
require 'ruby2js/filter/rails/playwright'
require 'ruby2js/filter/esm'

describe Ruby2JS::Filter::Rails::Playwright do
  def to_js(string)
    Ruby2JS.convert(string, {
      filters: [Ruby2JS::Filter::Rails::Playwright, Ruby2JS::Filter::ESM],
      eslevel: 2020,
      file: 'test/system/chat_system_test.rb',
      metadata: {'playwright' => true}
    }).to_s
  end

  describe "detection" do
    it "only activates with playwright metadata" do
      code = <<~RUBY
        class ChatSystemTest < ApplicationSystemTestCase
          test "works" do
            visit messages_url
          end
        end
      RUBY
      # Without metadata, should not transform
      result = Ruby2JS.convert(code, {
        filters: [Ruby2JS::Filter::Rails::Playwright],
        eslevel: 2020,
        file: 'test/system/chat_system_test.rb'
      }).to_s
      refute_includes result, 'test.describe'
      refute_includes result, '@playwright/test'
    end

    it "converts ApplicationSystemTestCase class to test.describe" do
      result = to_js(<<~RUBY)
        class ChatSystemTest < ApplicationSystemTestCase
          test "works" do
            visit messages_url
          end
        end
      RUBY
      assert_includes result, 'test.describe('
      assert_includes result, '"ChatSystem"'
      refute_includes result, 'ChatSystemTest'
    end

    it "converts ActionDispatch::SystemTestCase class to test.describe" do
      result = to_js(<<~RUBY)
        class ChatSystemTest < ActionDispatch::SystemTestCase
          test "works" do
            visit messages_url
          end
        end
      RUBY
      assert_includes result, 'test.describe('
      assert_includes result, '"ChatSystem"'
    end

    it "does not transform non-system test classes" do
      result = to_js(<<~RUBY)
        class ArticleTest < ActiveSupport::TestCase
          test "works" do
            true
          end
        end
      RUBY
      refute_includes result, 'test.describe'
    end
  end

  describe "imports" do
    it "emits Playwright test/expect import" do
      result = to_js(<<~RUBY)
        class ChatSystemTest < ApplicationSystemTestCase
          test "works" do
            visit messages_url
          end
        end
      RUBY
      assert_includes result, 'import { test, expect } from "@playwright/test"'
    end

    it "emits path helper imports from routes" do
      result = to_js(<<~RUBY)
        class ChatSystemTest < ApplicationSystemTestCase
          test "works" do
            visit messages_url
          end
        end
      RUBY
      assert_includes result, 'import { messages_path } from "../../config/routes.js"'
    end
  end

  describe "strips require" do
    it "strips require test_helper" do
      result = to_js(<<~RUBY)
        require "test_helper"
        class ChatSystemTest < ApplicationSystemTestCase
          test "works" do
            true
          end
        end
      RUBY
      refute_includes result, 'require'
      refute_includes result, 'test_helper'
    end
  end

  describe "test scaffolding" do
    it "creates test functions with { page } destructuring" do
      result = to_js(<<~RUBY)
        class ChatSystemTest < ApplicationSystemTestCase
          test "sends message" do
            visit messages_url
          end
        end
      RUBY
      assert_includes result, 'async ({ page }) =>'
      assert_includes result, '"sends message"'
    end

    it "converts setup to test.beforeEach" do
      result = to_js(<<~RUBY)
        class ChatSystemTest < ApplicationSystemTestCase
          setup do
            visit messages_url
          end
          test "works" do
            true
          end
        end
      RUBY
      assert_includes result, 'test.beforeEach(async ({ page }) =>'
    end

    it "converts teardown to test.afterEach" do
      result = to_js(<<~RUBY)
        class ChatSystemTest < ApplicationSystemTestCase
          teardown do
            visit messages_url
          end
          test "works" do
            true
          end
        end
      RUBY
      assert_includes result, 'test.afterEach(async ({ page }) =>'
    end
  end

  describe "visit" do
    it "converts visit url to await page.goto(path)" do
      result = to_js(<<~RUBY)
        class ChatSystemTest < ApplicationSystemTestCase
          test "visits page" do
            visit messages_url
          end
        end
      RUBY
      assert_includes result, 'await page.goto(messages_path().toString())'
    end
  end

  describe "fill_in" do
    it "converts fill_in with: to page.getByLabel().fill()" do
      result = to_js(<<~RUBY)
        class ChatSystemTest < ApplicationSystemTestCase
          test "fills in field" do
            fill_in "Your name", with: "Alice"
          end
        end
      RUBY
      assert_includes result, 'await page.getByLabel("Your name").fill("Alice")'
    end
  end

  describe "click_button" do
    it "converts click_button to page.getByRole button click" do
      result = to_js(<<~RUBY)
        class ChatSystemTest < ApplicationSystemTestCase
          test "clicks button" do
            click_button "Send"
          end
        end
      RUBY
      assert_includes result, 'page.getByRole("button", {name: "Send"}).click()'
    end
  end

  describe "click_on" do
    it "converts click_on to link.or(button).first().click()" do
      result = to_js(<<~RUBY)
        class ChatSystemTest < ApplicationSystemTestCase
          test "clicks link" do
            click_on "Home"
          end
        end
      RUBY
      assert_includes result, 'page.getByRole("link", {name: "Home"}).or(page.getByRole('
      assert_includes result, '{name: "Home"}'
      assert_includes result, '.first().click()'
    end
  end

  describe "assert_field" do
    it "converts assert_field with: to toHaveValue" do
      result = to_js(<<~RUBY)
        class ChatSystemTest < ApplicationSystemTestCase
          test "checks field" do
            assert_field "Type a message...", with: ""
          end
        end
      RUBY
      assert_includes result, 'expect(page.getByLabel("Type a message...")).toHaveValue("")'
    end

    it "converts assert_field without with: to toBeVisible" do
      result = to_js(<<~RUBY)
        class ChatSystemTest < ApplicationSystemTestCase
          test "checks field exists" do
            assert_field "Your name"
          end
        end
      RUBY
      assert_includes result, 'expect(page.getByLabel("Your name")).toBeVisible()'
    end
  end

  describe "assert_selector" do
    it "converts assert_selector with text: to toContainText" do
      result = to_js(<<~RUBY)
        class ChatSystemTest < ApplicationSystemTestCase
          test "checks content" do
            assert_selector "#messages", text: "Hello!"
          end
        end
      RUBY
      assert_includes result, 'expect(page.locator("#messages")).toContainText("Hello!")'
    end

    it "converts assert_selector without text: to toBeVisible" do
      result = to_js(<<~RUBY)
        class ChatSystemTest < ApplicationSystemTestCase
          test "checks element exists" do
            assert_selector "#messages"
          end
        end
      RUBY
      assert_includes result, 'expect(page.locator("#messages")).toBeVisible()'
    end
  end

  describe "assert_text" do
    it "converts assert_text to body toContainText" do
      result = to_js(<<~RUBY)
        class ChatSystemTest < ApplicationSystemTestCase
          test "checks text" do
            assert_text "Welcome"
          end
        end
      RUBY
      assert_includes result, 'expect(page.locator("body")).toContainText("Welcome")'
    end
  end

  describe "assert_no_selector" do
    it "converts assert_no_selector to not.toBeVisible" do
      result = to_js(<<~RUBY)
        class ChatSystemTest < ApplicationSystemTestCase
          test "checks no element" do
            assert_no_selector ".error"
          end
        end
      RUBY
      assert_includes result, 'expect(page.locator(".error")).not.toBeVisible()'
    end
  end

  describe "assert_no_text" do
    it "converts assert_no_text to not.toContainText" do
      result = to_js(<<~RUBY)
        class ChatSystemTest < ApplicationSystemTestCase
          test "checks no text" do
            assert_no_text "Error"
          end
        end
      RUBY
      assert_includes result, 'expect(page.locator("body")).not.toContainText("Error")'
    end
  end

  describe "defined? Playwright constant" do
    it "converts defined? Playwright to true" do
      result = to_js(<<~RUBY)
        class ChatSystemTest < ApplicationSystemTestCase
          test "playwright only" do
            x = defined? Playwright
          end
        end
      RUBY
      assert_includes result, 'true'
      refute_includes result, 'typeof'
    end

    it "leaves other defined? checks unchanged" do
      result = to_js(<<~RUBY)
        class ChatSystemTest < ApplicationSystemTestCase
          test "checks document" do
            skip unless defined? Document
          end
        end
      RUBY
      assert_includes result, 'typeof Document'
    end
  end

  describe "full integration" do
    it "transpiles complete chat system test" do
      result = to_js(<<~RUBY)
        require "test_helper"

        class ChatSystemTest < ApplicationSystemTestCase
          test "clears input after sending message" do
            visit messages_url
            fill_in "Your name", with: "Alice"
            fill_in "Type a message...", with: "Hello!"
            click_button "Send"
            assert_field "Type a message...", with: ""
          end

          test "creates message and displays it" do
            visit messages_url
            fill_in "Your name", with: "Alice"
            fill_in "Type a message...", with: "Hello!"
            click_button "Send"
            visit messages_url
            assert_selector "#messages", text: "Hello!"
          end
        end
      RUBY

      # Imports
      assert_includes result, 'import { test, expect } from "@playwright/test"'
      assert_includes result, 'import { messages_path } from "../../config/routes.js"'

      # No test_helper
      refute_includes result, 'test_helper'

      # test.describe wrapper
      assert_includes result, 'test.describe("ChatSystem"'

      # Test functions with { page }
      assert_includes result, 'async ({ page }) =>'

      # Capybara transforms
      assert_includes result, 'page.goto(messages_path().toString())'
      assert_includes result, 'page.getByLabel("Your name").fill("Alice")'
      assert_includes result, 'page.getByRole("button", {name: "Send"}).click()'
      assert_includes result, 'expect(page.getByLabel("Type a message...")).toHaveValue("")'
      assert_includes result, 'expect(page.locator("#messages")).toContainText("Hello!")'
    end
  end

  describe "beforeEach reset" do
    it "injects test.beforeEach with /__test/reset call and fixture loading" do
      result = to_js(<<~RUBY)
        class ChatSystemTest < ApplicationSystemTestCase
          test "shows page" do
            visit messages_url
          end
        end
      RUBY
      assert_includes result, 'let _fixtures = {}'
      assert_includes result, 'test.beforeEach(async ({ request }) =>'
      assert_includes result, 'request.post("/__test/reset")'
      assert_includes result, 'Object.assign(_fixtures, await(resp.json()))'
    end
  end

  describe "accept_confirm" do
    it "converts accept_confirm block to page.once dialog handler" do
      result = to_js(<<~RUBY)
        class ChatSystemTest < ApplicationSystemTestCase
          test "deletes item" do
            accept_confirm do
              click_on "Delete"
            end
          end
        end
      RUBY
      assert_includes result, 'page.once("dialog", dialog => dialog.accept())'
      assert_includes result, '.first().click()'
    end
  end

  describe "select" do
    it "converts select from: to page.getByLabel().selectOption()" do
      result = to_js(<<~RUBY)
        class StudiosSystemTest < ApplicationSystemTestCase
          test "selects option" do
            select "Three", from: "Pair"
          end
        end
      RUBY
      assert_includes result, 'await page.getByLabel("Pair").selectOption("Three")'
    end
  end

  describe "find().hover()" do
    it "converts find with match: :first and hover to locator().first().hover()" do
      result = to_js(<<~RUBY)
        class StudiosSystemTest < ApplicationSystemTestCase
          test "hovers element" do
            find("li.group", match: :first).hover
          end
        end
      RUBY
      assert_includes result, 'page.locator("li.group").first().hover()'
    end

    it "converts find without match option to locator().hover()" do
      result = to_js(<<~RUBY)
        class StudiosSystemTest < ApplicationSystemTestCase
          test "hovers element" do
            find("li.group").hover
          end
        end
      RUBY
      assert_includes result, 'page.locator("li.group").hover()'
      refute_includes result, 'first()'
    end
  end

  describe "click_on with match:" do
    it "strips match: option (already uses .first())" do
      result = to_js(<<~RUBY)
        class StudiosSystemTest < ApplicationSystemTestCase
          test "clicks first match" do
            click_on "Unpair", match: :first
          end
        end
      RUBY
      assert_includes result, 'page.getByRole("link", {name: "Unpair"})'
      assert_includes result, '.first().click()'
    end
  end

  describe "within" do
    it "scopes assertions to a locator" do
      result = to_js(<<~RUBY)
        class StudiosSystemTest < ApplicationSystemTestCase
          test "checks within scope" do
            within("ul") do
              assert_no_text "Three"
              assert_text "Two"
            end
          end
        end
      RUBY
      assert_includes result, 'let _el = page.locator("ul:visible")'
      assert_includes result, 'expect(_el).not.toContainText("Three")'
      assert_includes result, 'expect(_el).toContainText("Two")'
      refute_includes result, 'page.locator("body")'
    end

    it "uses page.locator(body) outside within" do
      result = to_js(<<~RUBY)
        class StudiosSystemTest < ApplicationSystemTestCase
          test "checks body" do
            assert_text "Hello"
          end
        end
      RUBY
      assert_includes result, 'expect(page.locator("body")).toContainText("Hello")'
    end
  end
end
