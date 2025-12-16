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
      assert_includes result, 'export const Routes'
    end
  end

  describe "root route" do
    it "generates root route entry" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          root 'articles#index'
        end
      RUBY
      assert_includes result, 'path: "/"'
      assert_includes result, 'controller: "ArticlesController"'
      assert_includes result, 'action: "index!"'
    end

    it "generates root_path helper" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          root 'articles#index'
        end
      RUBY
      assert_includes result, 'function root_path()'
      assert_includes result, 'return "/"'
    end
  end

  describe "resources" do
    it "generates all 7 RESTful routes" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          resources :articles
        end
      RUBY
      # Check for all 7 RESTful actions
      assert_includes result, 'action: "index!"'
      assert_includes result, 'action: "$new"'
      assert_includes result, 'action: "create"'
      assert_includes result, 'action: "show"'
      assert_includes result, 'action: "edit"'
      assert_includes result, 'action: "update"'
      assert_includes result, 'action: "destroy"'
    end

    it "generates correct paths" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          resources :articles
        end
      RUBY
      assert_includes result, 'path: "/articles"'
      assert_includes result, 'path: "/articles/new"'
      assert_includes result, 'path: "/articles/:id"'
      assert_includes result, 'path: "/articles/:id/edit"'
    end

    it "generates correct HTTP methods" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          resources :articles
        end
      RUBY
      assert_includes result, 'method: "GET"'
      assert_includes result, 'method: "POST"'
      assert_includes result, 'method: "PATCH"'
      assert_includes result, 'method: "DELETE"'
    end

    it "respects only: option" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          resources :articles, only: [:index, :show]
        end
      RUBY
      assert_includes result, 'action: "index!"'
      assert_includes result, 'action: "show"'
      refute_includes result, 'action: "create"'
      refute_includes result, 'action: "$new"'
    end

    it "respects except: option" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          resources :articles, except: [:destroy]
        end
      RUBY
      assert_includes result, 'action: "index!"'
      assert_includes result, 'action: "show"'
      refute_includes result, 'action: "destroy"'
    end
  end

  describe "nested resources" do
    it "generates nested routes with parent param" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          resources :articles do
            resources :comments, only: [:create, :destroy]
          end
        end
      RUBY
      assert_includes result, 'path: "/articles/:article_id/comments"'
      assert_includes result, 'path: "/articles/:article_id/comments/:id"'
    end

    it "generates nested path helpers" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          resources :articles do
            resources :comments, only: [:create]
          end
        end
      RUBY
      assert_includes result, 'function comments_path(article)'
      assert_includes result, '/articles/${extract_id(article)}/comments'
    end
  end

  describe "custom routes" do
    it "handles get route" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          get 'about', to: 'pages#about'
        end
      RUBY
      assert_includes result, 'path: "/about"'
      assert_includes result, 'controller: "PagesController"'
      assert_includes result, 'action: "about"'
      assert_includes result, 'method: "GET"'
    end

    it "handles post route" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          post 'contact', to: 'pages#contact'
        end
      RUBY
      assert_includes result, 'path: "/contact"'
      assert_includes result, 'method: "POST"'
    end

    it "handles patch route" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          patch 'settings', to: 'settings#update'
        end
      RUBY
      assert_includes result, 'method: "PATCH"'
    end

    it "handles delete route" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          delete 'session', to: 'sessions#destroy'
        end
      RUBY
      assert_includes result, 'method: "DELETE"'
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
      assert_includes result, 'return "/articles"'
    end

    it "generates member path helper with param" do
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
      assert_includes result, '/articles/new'
    end

    it "generates edit path helper with param" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          resources :articles
        end
      RUBY
      assert_includes result, 'function edit_article_path(article)'
      assert_includes result, 'extract_id(article)'
      assert_includes result, '/edit'
    end

    it "generates extract_id helper when needed" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          resources :articles
        end
      RUBY
      assert_includes result, 'function extract_id(obj)'
      assert_includes result, 'obj?.id()'
    end
  end

  describe "action name transformation" do
    it "transforms index to index!" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          resources :articles, only: [:index]
        end
      RUBY
      assert_includes result, 'action: "index!"'
    end

    it "transforms new to $new" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          resources :articles, only: [:new]
        end
      RUBY
      assert_includes result, 'action: "$new"'
    end
  end

  describe "export" do
    it "exports the Routes module" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          root 'home#index'
        end
      RUBY
      assert_includes result, 'export const Routes'
    end

    it "exports routes method" do
      result = to_js(<<~RUBY)
        Rails.application.routes.draw do
          root 'home#index'
        end
      RUBY
      assert_includes result, 'return {'
      assert_includes result, 'routes'
    end
  end
end
