# Rails Playwright filter - transforms Capybara-style system tests to Playwright tests
#
# This filter transforms the same test/system/*.rb files that the test filter
# handles for vitest/jsdom, but targets Playwright instead. It is gated on
# metadata['playwright'] so it only activates when explicitly requested.
#
# Two-tier testing model:
# - `juntos test`  → vitest/jsdom (fast, every commit)
# - `juntos e2e`   → Playwright (thorough, real browser, periodic)
#
# Transform mapping:
#   visit url                         → await page.goto(url_path())
#   fill_in "X", with: "Y"           → await page.getByLabel("X").fill("Y")
#   click_button "Send"               → await page.getByRole("button", {name: "Send"}).click()
#   click_on "Link"                   → await page.getByRole("link", {name: "Link"}).click()
#   assert_field "X", with: "Y"       → await expect(page.getByLabel("X")).toHaveValue("Y")
#   assert_selector "css", text: "T"  → await expect(page.locator("css")).toContainText("T")
#   assert_selector "css"             → await expect(page.locator("css")).toBeVisible()
#   assert_text "T"                   → await expect(page.locator("body")).toContainText("T")
#   assert_no_selector "css"          → await expect(page.locator("css")).not.toBeVisible()
#   assert_no_text "T"                → await expect(page.locator("body")).not.toContainText("T")
#   select "X", from: "Y"            → await page.getByLabel("Y").selectOption("X")
#   find("css", match: :first).hover → await page.locator("css").first().hover()
#   within("css") { ... }            → const _el = page.locator("css"); <scoped assertions>
#   defined? Playwright               → true
#
# Usage:
#   Ruby2JS.convert(source, filters: [...], metadata: { 'playwright' => true })

require 'ruby2js'

module Ruby2JS
  module Filter
    module Rails
      module Playwright
        include SEXP

        def initialize(*args)
          super
          @playwright_active = false
          @playwright_describe_depth = 0
          @playwright_path_helpers = []
          @playwright_within_var = nil
        end

        # Handle class-based test definitions
        def on_class(node)
          return super unless is_playwright_file

          class_name, superclass, body = node.children

          # Only handle system test classes
          return super unless superclass&.type == :const
          superclass_name = playwright_const_name(superclass)
          return super unless superclass_name.include?('SystemTestCase')

          # Strip "Test" suffix for describe name
          name = class_name.children.last.to_s
          describe_name = name.end_with?('Test') ? name[0..-5] : name

          result = nil
          begin
            @playwright_active = true
            @playwright_describe_depth += 1

            # Transform class body
            transformed_body = process(body)

            # Build: test.beforeEach(async ({ request }) => {
            #   await request.post("/__test/reset")
            # })
            reset_call = s(:send, nil, :await,
              s(:send, s(:lvar, :request), :post, s(:str, '/__test/reset')))
            before_each = s(:send, s(:lvar, :test), :beforeEach,
              s(:async, nil,
                s(:args, s(:kwarg, :request)),
                reset_call))

            # Wrap body with beforeEach
            body_with_hook = if transformed_body&.type == :begin
              s(:begin, before_each, *transformed_body.children)
            elsif transformed_body
              s(:begin, before_each, transformed_body)
            else
              before_each
            end

            # Build: test.describe("Name", () => { ... })
            describe_block = s(:block,
              s(:send, s(:lvar, :test), :describe, s(:str, describe_name)),
              s(:args),
              body_with_hook)

            # Build imports and path helper imports
            imports = []
            imports.push(s(:import, '@playwright/test',
              [s(:const, nil, :test), s(:const, nil, :expect)]))

            if @playwright_path_helpers.any?
              path_consts = @playwright_path_helpers.map { |name| s(:const, nil, name.to_sym) }
              imports.push(s(:import, ['../config/routes.js'], path_consts))
            end

            result = s(:begin, *imports, describe_block)
          ensure
            @playwright_active = false
            @playwright_describe_depth -= 1
            @playwright_path_helpers = []
          end
          result
        end

        # Handle test/setup/teardown blocks
        def on_block(node)
          return super unless @playwright_active

          call = node.children.first
          return super unless call.type == :send && call.children.first.nil?

          method = call.children[1]

          case method
          when :test
            return super unless @playwright_describe_depth > 0
            args = call.children[2..-1]
            body = node.children.last

            processed_body = process(body)

            # Create async arrow function with { page } destructuring
            async_fn = s(:async, nil,
              s(:args, s(:kwarg, :page)),
              processed_body)

            # Build: test("name", async ({ page }) => { ... })
            s(:send, nil, :test, *process_all(args), async_fn)

          when :setup
            return super unless @playwright_describe_depth > 0
            body = node.children.last
            processed_body = process(body)

            async_fn = s(:async, nil,
              s(:args, s(:kwarg, :page)),
              processed_body)

            s(:send, s(:lvar, :test), :beforeEach, async_fn)

          when :teardown
            return super unless @playwright_describe_depth > 0
            body = node.children.last
            processed_body = process(body)

            async_fn = s(:async, nil,
              s(:args, s(:kwarg, :page)),
              processed_body)

            s(:send, s(:lvar, :test), :afterEach, async_fn)

          when :within
            # within("ul") { assert_text "Two" } →
            #   const _el = page.locator("ul");
            #   await expect(_el).toContainText("Two")
            return super unless @playwright_describe_depth > 0
            call_args = call.children[2..-1]
            return super if call_args.empty?
            selector = process(call_args.first)

            # Save previous within var (supports nesting)
            prev_within = @playwright_within_var
            @playwright_within_var = :_el

            body = node.children.last
            processed_body = process(body)

            @playwright_within_var = prev_within

            # const _el = page.locator("selector")
            assign = s(:lvasgn, :_el,
              s(:send, s(:lvar, :page), :locator, selector))

            s(:begin, assign, processed_body)

          when :accept_confirm
            # accept_confirm { click_on "X" } →
            #   page.once("dialog", dialog => dialog.accept());
            #   <block body>
            return super unless @playwright_describe_depth > 0
            body = node.children.last
            processed_body = process(body)

            # page.once("dialog", dialog => dialog.accept())
            dialog_handler = s(:send, s(:lvar, :page), :once, s(:str, 'dialog'),
              s(:block, s(:send, nil, :proc), s(:args, s(:arg, :dialog)),
                s(:send!, s(:lvar, :dialog), :accept)))

            if processed_body&.type == :begin
              s(:begin, dialog_handler, *processed_body.children)
            else
              s(:begin, dialog_handler, processed_body)
            end

          else
            super
          end
        end

        # Transform Capybara methods to Playwright API
        def on_send(node)
          return super unless is_playwright_file

          target, method, *args = node.children

          # Strip require "test_helper" (top-level, before class)
          if target.nil? && method == :require && args.length == 1 &&
             args.first.type == :str && args.first.children.first == 'test_helper'
            return s(:hide)
          end

          # Only transform inside describe blocks
          if @playwright_describe_depth > 0
            # find("selector", match: :first).hover → await page.locator("selector").first().hover()
            if target.nil? == false && method == :hover && target.type == :send &&
               target.children[1] == :find
              find_args = target.children[2..-1]
              return nil if find_args.empty?
              selector = process(find_args.first)
              locator = s(:send, s(:lvar, :page), :locator, selector)
              # Check for match: :first option
              if find_args.length >= 2 && find_args[1].type == :hash
                find_args[1].children.each do |pair|
                  if pair.children[0].type == :sym && pair.children[0].children[0] == :match
                    locator = s(:send!, locator, :first)
                  end
                end
              end
              return s(:send, nil, :await,
                s(:send!, locator, :hover))
            end

            if target.nil?
              result = transform_capybara_to_playwright(method, args)
              return result if result

              # URL helper -> path helper
              if method.to_s.end_with?('_url')
                return transform_url_to_path_playwright(method, args)
              end
            end
          end

          super
        end

        # defined? Playwright → true (compile-time constant)
        def on_defined?(node)
          return super unless is_playwright_file
          child = node.children.first
          if child.type == :const && child.children[1] == :Playwright
            return s(:true)
          end
          super
        end

        private

        def is_playwright_file
          @options[:metadata]&.[]('playwright')
        end

        # Get fully qualified constant name from AST node
        def playwright_const_name(node)
          return '' unless node&.type == :const
          parent = node.children[0]
          name = node.children[1].to_s
          parent ? "#{playwright_const_name(parent)}::#{name}" : name
        end

        def transform_url_to_path_playwright(method, args)
          path_method = method.to_s.sub(/_url$/, '_path').to_sym
          path_str = path_method.to_s
          @playwright_path_helpers << path_str unless @playwright_path_helpers.include?(path_str)

          if args.empty?
            s(:send!, nil, path_method)
          else
            s(:send, nil, path_method, *process_all(args))
          end
        end

        def transform_capybara_to_playwright(method, args)
          case method
          when :visit
            # visit messages_url → await page.goto(messages_path())
            return nil if args.empty?
            url_node = process(args.first)
            s(:send, nil, :await,
              s(:send, s(:lvar, :page), :goto, url_node))

          when :fill_in
            # fill_in "X", with: "Y" → await page.getByLabel("X").fill("Y")
            return nil if args.length < 2
            locator = process(args[0])
            value_hash = args[1]
            return nil unless value_hash.type == :hash
            value_node = nil
            value_hash.children.each do |pair|
              if pair.children[0].type == :sym && pair.children[0].children[0] == :with
                value_node = process(pair.children[1])
              end
            end
            return nil unless value_node
            s(:send, nil, :await,
              s(:send,
                s(:send, s(:lvar, :page), :getByLabel, locator),
                :fill, value_node))

          when :click_button
            # click_button "Send" → await page.getByRole("button", {name: "Send"}).click()
            return nil if args.empty?
            text = process(args.first)
            s(:send, nil, :await,
              s(:send!,
                s(:send, s(:lvar, :page), :getByRole, s(:str, 'button'),
                  s(:hash, s(:pair, s(:sym, :name), text))),
                :click))

          when :click_on
            # click_on "X" → await page.getByRole("link", {name: "X"})
            #                   .or(page.getByRole("button", {name: "X"})).first().click()
            # click_on "X", match: :first → same (match: option is stripped)
            return nil if args.empty?
            text = process(args.first)
            link_locator = s(:send, s(:lvar, :page), :getByRole, s(:str, 'link'),
              s(:hash, s(:pair, s(:sym, :name), text)))
            button_locator = s(:send, s(:lvar, :page), :getByRole, s(:str, 'button'),
              s(:hash, s(:pair, s(:sym, :name), text)))
            s(:send, nil, :await,
              s(:send!,
                s(:send!, s(:send, link_locator, :or, button_locator), :first),
                :click))

          when :select
            # select "Three", from: "Pair" → await page.getByLabel("Pair").selectOption("Three")
            return nil if args.empty?
            value = process(args[0])
            from_node = nil
            if args.length >= 2 && args[1].type == :hash
              args[1].children.each do |pair|
                if pair.children[0].type == :sym && pair.children[0].children[0] == :from
                  from_node = process(pair.children[1])
                end
              end
            end
            return nil unless from_node
            s(:send, nil, :await,
              s(:send,
                s(:send, s(:lvar, :page), :getByLabel, from_node),
                :selectOption, value))

          when :assert_field
            # assert_field "X", with: "Y" → await expect(page.getByLabel("X")).toHaveValue("Y")
            return nil if args.empty?
            locator = process(args[0])
            if args.length >= 2 && args[1].type == :hash
              value_node = nil
              args[1].children.each do |pair|
                if pair.children[0].type == :sym && pair.children[0].children[0] == :with
                  value_node = process(pair.children[1])
                end
              end
              if value_node
                return s(:send, nil, :await,
                  s(:send,
                    s(:send, nil, :expect,
                      s(:send, s(:lvar, :page), :getByLabel, locator)),
                    :toHaveValue, value_node))
              end
            end
            # assert_field "X" (existence) → await expect(page.getByLabel("X")).toBeVisible()
            s(:send, nil, :await,
              s(:send!,
                s(:send, nil, :expect,
                  s(:send, s(:lvar, :page), :getByLabel, locator)),
                :toBeVisible))

          when :assert_selector
            # assert_selector "css", text: "T" → await expect(page.locator("css")).toContainText("T")
            # assert_selector "css"            → await expect(page.locator("css")).toBeVisible()
            return nil if args.empty?
            selector = process(args[0])
            if args.length >= 2 && args[1].type == :hash
              text_node = nil
              args[1].children.each do |pair|
                if pair.children[0].type == :sym && pair.children[0].children[0] == :text
                  text_node = process(pair.children[1])
                end
              end
              if text_node
                return s(:send, nil, :await,
                  s(:send,
                    s(:send, nil, :expect,
                      s(:send, s(:lvar, :page), :locator, selector)),
                    :toContainText, text_node))
              end
            end
            s(:send, nil, :await,
              s(:send!,
                s(:send, nil, :expect,
                  s(:send, s(:lvar, :page), :locator, selector)),
                :toBeVisible))

          when :assert_text
            # assert_text "T" → await expect(page.locator("body")).toContainText("T")
            # Inside within: → await expect(_el).toContainText("T")
            return nil if args.empty?
            text = process(args.first)
            container = if @playwright_within_var
              s(:lvar, @playwright_within_var)
            else
              s(:send, s(:lvar, :page), :locator, s(:str, 'body'))
            end
            s(:send, nil, :await,
              s(:send,
                s(:send, nil, :expect, container),
                :toContainText, text))

          when :assert_no_selector
            # assert_no_selector "css" → await expect(page.locator("css")).not.toBeVisible()
            return nil if args.empty?
            selector = process(args[0])
            s(:send, nil, :await,
              s(:send!,
                s(:attr,
                  s(:send, nil, :expect,
                    s(:send, s(:lvar, :page), :locator, selector)),
                  :not),
                :toBeVisible))

          when :assert_no_text
            # assert_no_text "T" → await expect(page.locator("body")).not.toContainText("T")
            # Inside within: → await expect(_el).not.toContainText("T")
            return nil if args.empty?
            text = process(args.first)
            container = if @playwright_within_var
              s(:lvar, @playwright_within_var)
            else
              s(:send, s(:lvar, :page), :locator, s(:str, 'body'))
            end
            s(:send, nil, :await,
              s(:send,
                s(:attr,
                  s(:send, nil, :expect, container),
                  :not),
                :toContainText, text))

          else
            nil
          end
        end
      end
    end

    DEFAULTS.push Rails::Playwright
  end
end
