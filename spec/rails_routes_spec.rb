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
      # Now exports Application, routes, plus path helpers
      assert_includes result, 'export { Application, routes, root_path }'
    end
  end

  describe "imports" do
    it "imports Router, Application, createContext, formData, and handleFormResult from rails.js" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          root 'articles#index'
        end
      RUBY
      assert_includes result, 'import { Router, Application, createContext, formData, handleFormResult } from "../lib/rails.js"'
    end

    it "imports migrations and Seeds" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          root 'articles#index'
        end
      RUBY
      assert_includes result, 'import { migrations } from "../db/migrate/index.js"'
      assert_includes result, 'import { Seeds } from "../db/seeds.js"'
    end

    it "imports controllers based on resources" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          resources :articles
        end
      RUBY
      assert_includes result, 'import { ArticlesController } from "../app/controllers/articles_controller.js"'
    end

    it "imports createPathHelper for path helper methods" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          resources :articles
        end
      RUBY
      assert_includes result, 'import { createPathHelper } from "juntos/path_helper.mjs"'
    end
  end

  describe "root route" do
    it "generates Router.root() call" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          root 'articles#index'
        end
      RUBY
      assert_includes result, 'Router.root("/", ArticlesController, "index")'
    end

    it "generates Router.root() with base path for subdirectory hosting" do
      result = to_js(<<~RUBY, base: '/blog')
        Rails.application.routes.draw do
          root 'articles#index'
        end
      RUBY
      assert_includes result, 'Router.root("/blog/", ArticlesController, "index")'
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

  describe "routes dispatch object" do
    it "generates routes object for resources" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          resources :articles
        end
      RUBY
      assert_includes result, 'const routes = {'
      assert_includes result, 'articles: {'
      assert_includes result, 'article: {'
      # Context-aware controller calls
      assert_includes result, 'ArticlesController.create(context, params)'
      assert_includes result, 'ArticlesController.destroy(context, id)'
    end

    it "generates nested routes for nested resources" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          resources :articles do
            resources :comments
          end
        end
      RUBY
      assert_includes result, 'article_comments: {'
      assert_includes result, 'article_comment: {'
      # Context-aware controller calls (may have newlines in output)
      assert_includes result, 'CommentsController.create'
      assert_includes result, 'CommentsController.destroy(context'
    end
  end

  describe "Application.configure" do
    it "configures Application with migrations and seeds" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          root 'home#index'
        end
      RUBY
      assert_includes result, 'Application.configure({migrations: migrations, seeds: Seeds})'
    end
  end

  describe "export" do
    it "exports Application" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          root 'home#index'
        end
      RUBY
      assert_includes result, 'export { Application'
    end

    it "exports path helpers" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          resources :articles
        end
      RUBY
      assert_includes result, 'articles_path'
      assert_includes result, 'article_path'
      assert_includes result, 'new_article_path'
      assert_includes result, 'edit_article_path'
    end
  end

  describe "path helpers" do
    it "generates collection path helper" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          resources :articles
        end
      RUBY
      assert_includes result, 'function articles_path()'
      assert_includes result, 'return createPathHelper("/articles")'
    end

    it "generates member path helper with extract_id" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          resources :articles
        end
      RUBY
      assert_includes result, 'function article_path(article)'
      assert_includes result, 'extract_id(article)'
    end

    it "generates new path helper" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          resources :articles
        end
      RUBY
      assert_includes result, 'function new_article_path()'
      assert_includes result, 'return createPathHelper("/articles/new")'
    end

    it "generates edit path helper" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          resources :articles
        end
      RUBY
      assert_includes result, 'function edit_article_path(article)'
      assert_includes result, '/edit'
    end

    it "generates extract_id helper" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          resources :articles
        end
      RUBY
      assert_includes result, 'function extract_id(obj)'
      assert_includes result, 'obj.id'
    end

    it "generates nested resource path helpers" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          resources :articles do
            resources :comments, only: [:create, :destroy]
          end
        end
      RUBY
      # Rails convention: nested resources are prefixed with parent name
      assert_includes result, 'function article_comments_path(article)'
      assert_includes result, '/articles/'
      assert_includes result, '/comments'
    end

    it "generates root_path helper" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          root 'articles#index'
        end
      RUBY
      assert_includes result, 'function root_path()'
      assert_includes result, 'return createPathHelper("/")'
    end

    it "generates valid empty module when no path helpers exist" do
      result = to_js(<<~RUBY, paths_only: true)
        Rails.application.routes.draw do
          get '/health', to: 'health#show'
        end
      RUBY
      refute_includes result, 'export []'
    end
  end

  describe "namespace" do
    it "generates path helpers with namespace prefix" do
      result = to_js(<<~RUBY, paths_only: true)
        Rails.application.routes.draw do
          namespace :account do
            resource :settings
            resources :exports, only: [:create, :show]
          end
        end
      RUBY
      assert_includes result, 'function account_settings_path()'
      assert_includes result, '"/account/settings"'
      assert_includes result, 'function account_exports_path()'
      assert_includes result, '"/account/exports"'
      assert_includes result, 'function account_export_path('
      assert_includes result, '/account/exports/'
    end

    it "generates path helpers with nested namespaces" do
      result = to_js(<<~RUBY, paths_only: true)
        Rails.application.routes.draw do
          namespace :events do
            namespace :day_timeline do
              resources :columns, only: :show
            end
          end
        end
      RUBY
      assert_includes result, 'function events_day_timeline_column_path('
      assert_includes result, '/events/day_timeline/columns/'
    end
  end

  describe "scope" do
    it "scope module: is transparent for paths" do
      result = to_js(<<~RUBY, paths_only: true)
        Rails.application.routes.draw do
          resources :users do
            scope module: :users do
              resource :avatar
            end
          end
        end
      RUBY
      assert_includes result, 'function user_avatar_path(user)'
      assert_includes result, '/users/'
      assert_includes result, '/avatar'
      # No extra "users" segment from the scope
      refute_includes result, '/users/users/'
    end

    it "scope as: adds naming prefix without URL change" do
      result = to_js(<<~RUBY, paths_only: true)
        Rails.application.routes.draw do
          resource :signup, only: %i[ new create ] do
            collection do
              scope module: :signups, as: :signup do
                resource :completion, only: %i[ new create ]
              end
            end
          end
        end
      RUBY
      # collection clears parent prefix; scope as: :signup adds it back
      assert_includes result, 'function new_signup_completion_path()'
      assert_includes result, '"/signup/completion/new"'
    end
  end

  describe "collection" do
    it "removes parent :id from path for collection-level resources" do
      result = to_js(<<~RUBY, paths_only: true)
        Rails.application.routes.draw do
          resources :notifications do
            scope module: :notifications do
              collection do
                resource :bulk_reading, only: :create
              end
            end
          end
        end
      RUBY
      assert_includes result, 'function bulk_reading_path()'
      assert_includes result, '"/notifications/bulk_reading"'
      # Should NOT have :id in path
      refute_includes result, 'notification_id'
    end

    it "generates path helpers for on: :collection custom routes" do
      result = to_js(<<~RUBY, paths_only: true)
        Rails.application.routes.draw do
          resources :notifications do
            get "tray", to: "trays#show", on: :collection, as: :notification_tray
          end
        end
      RUBY
      assert_includes result, 'function notification_tray_path()'
      assert_includes result, '"/notifications/tray"'
    end
  end

  describe "custom routes with as:" do
    it "generates path helper for get with as:" do
      result = to_js(<<~RUBY, paths_only: true)
        Rails.application.routes.draw do
          get "join/:code", to: "join_codes#new", as: :join
        end
      RUBY
      assert_includes result, 'function join_path(code)'
      assert_includes result, '/join/'
    end

    it "generates path helper for hashrocket syntax" do
      result = to_js(<<~RUBY, paths_only: true)
        Rails.application.routes.draw do
          get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
        end
      RUBY
      assert_includes result, 'function pwa_manifest_path()'
      assert_includes result, '"/manifest"'
    end
  end

  describe "singular resource with only: :create" do
    it "generates path helper for create-only singular resources" do
      result = to_js(<<~RUBY, paths_only: true)
        Rails.application.routes.draw do
          resources :cards do
            scope module: :cards do
              resource :self_assignment, only: :create
            end
          end
        end
      RUBY
      assert_includes result, 'function card_self_assignment_path(card)'
    end
  end

  describe "param: option" do
    it "uses custom param in paths" do
      result = to_js(<<~RUBY, paths_only: true)
        Rails.application.routes.draw do
          resources :email_addresses, param: :token do
            resource :confirmation
          end
        end
      RUBY
      assert_includes result, 'function email_address_path('
      # Custom param :token is used in nesting (nested resources reference parent by token)
      assert_includes result, 'function email_address_confirmation_path(token)'
      assert_includes result, '/email_addresses/'
    end
  end
end
