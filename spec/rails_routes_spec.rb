gem 'minitest'
require 'minitest/autorun'
require 'ruby2js/filter/rails/routes'
require 'ruby2js/filter/esm'

describe Ruby2JS::Filter::Rails::Routes do
  def to_js(string, options = {})
    Ruby2JS.convert(string, {
      filters: [Ruby2JS::Filter::Rails::Routes, Ruby2JS::Filter::ESM],
      eslevel: 2020
    }.merge(options)).to_s
  end

  describe "detection" do
    it "detects Rails.application.routes.draw block" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          root 'home#index'
        end
      RUBY
      assert_includes result, 'export { Application }'
    end
  end

  describe "imports" do
    it "imports Router, Application, and setupFormHandlers from rails.js" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          root 'articles#index'
        end
      RUBY
      assert_includes result, 'import { Router, Application, setupFormHandlers } from "../lib/rails.js"'
    end

    it "imports Schema and Seeds" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          root 'articles#index'
        end
      RUBY
      assert_includes result, 'import { Schema } from "./schema.js"'
      assert_includes result, 'import { Seeds } from "../db/seeds.js"'
    end

    it "imports controllers based on resources" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          resources :articles
        end
      RUBY
      assert_includes result, 'import { ArticlesController } from "../controllers/articles_controller.js"'
    end
  end

  describe "root route" do
    it "generates Router.root() call" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          root 'articles#index'
        end
      RUBY
      assert_includes result, 'Router.root("/articles")'
    end
  end

  describe "resources" do
    it "generates Router.resources() call" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          resources :articles
        end
      RUBY
      assert_includes result, 'Router.resources("articles", ArticlesController)'
    end

    it "respects only: option" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          resources :articles, only: [:index, :show]
        end
      RUBY
      assert_includes result, 'Router.resources('
      assert_includes result, '"articles"'
      assert_includes result, 'ArticlesController'
      assert_includes result, 'only: ["index", "show"]'
    end

    it "respects except: option (not passed to Router)" do
      # except: is handled at build time, not passed to Router
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          resources :articles, except: [:destroy]
        end
      RUBY
      assert_includes result, 'Router.resources("articles", ArticlesController)'
      refute_includes result, 'except'
    end
  end

  describe "nested resources" do
    it "generates nested option for Router.resources()" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          resources :articles do
            resources :comments, only: [:create, :destroy]
          end
        end
      RUBY
      assert_includes result, 'Router.resources("articles", ArticlesController, {nested:'
      assert_includes result, 'name: "comments"'
      assert_includes result, 'controller: CommentsController'
      assert_includes result, 'only: ["create", "destroy"]'
    end

    it "imports nested controllers" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          resources :articles do
            resources :comments
          end
        end
      RUBY
      assert_includes result, 'import { ArticlesController }'
      assert_includes result, 'import { CommentsController }'
    end
  end

  describe "setupFormHandlers" do
    it "generates setupFormHandlers for resources" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          resources :articles
        end
      RUBY
      assert_includes result, 'setupFormHandlers(['
      assert_includes result, 'resource: "articles"'
      assert_includes result, 'confirmDelete:'
    end

    it "includes parent for nested resources" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          resources :articles do
            resources :comments
          end
        end
      RUBY
      assert_includes result, 'resource: "comments"'
      assert_includes result, 'parent: "articles"'
    end
  end

  describe "Application.configure" do
    it "configures Application with schema and seeds" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          root 'home#index'
        end
      RUBY
      assert_includes result, 'Application.configure({schema: Schema, seeds: Seeds})'
    end
  end

  describe "export" do
    it "exports Application" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          root 'home#index'
        end
      RUBY
      assert_includes result, 'export { Application }'
    end
  end
end
