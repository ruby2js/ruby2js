require 'minitest/autorun'
require 'ruby2js/svelte_component_transformer'

describe Ruby2JS::SvelteComponentTransformer do
  def transform(source, options = {})
    Ruby2JS::SvelteComponentTransformer.transform(source, options)
  end

  describe "basic transformation" do
    it "transforms a simple component with template" do
      source = <<~RUBY
        @message = "Hello"
        __END__
        <h1>{message}</h1>
      RUBY

      result = transform(source)

      _(result.errors).must_be_empty
      _(result.component).must_include '<script>'
      _(result.component).must_include '</script>'
      _(result.template).must_include '{message}'
    end

    it "returns error when no template present" do
      source = "@message = 'Hello'"
      result = transform(source)

      _(result.errors).wont_be_empty
      _(result.errors.first[:type]).must_equal 'noTemplate'
    end
  end

  describe "instance variables to let declarations" do
    it "detects instance variable assignments" do
      source = <<~RUBY
        @count = 0
        @name = nil
        __END__
        <p>{count}</p>
      RUBY

      result = transform(source)

      # Svelte uses let declarations, which Ruby2JS generates
      _(result.script).must_include 'count'
    end
  end

  describe "lifecycle hooks" do
    it "imports onMount for on_mount hook" do
      source = <<~RUBY
        @data = nil

        def on_mount
          @data = "loaded"
        end
        __END__
        <p>{data}</p>
      RUBY

      result = transform(source)

      _([*result.imports[:svelte]]).must_include 'onMount'
      _(result.script).must_include "import { onMount } from 'svelte'"
    end

    it "imports onDestroy for on_destroy hook" do
      source = <<~RUBY
        def on_destroy
          cleanup
        end
        __END__
        <p>Test</p>
      RUBY

      result = transform(source)

      _([*result.imports[:svelte]]).must_include 'onDestroy'
    end

    it "imports beforeUpdate for before_update hook" do
      source = <<~RUBY
        def before_update
          prepare
        end
        __END__
        <p>Test</p>
      RUBY

      result = transform(source)

      _([*result.imports[:svelte]]).must_include 'beforeUpdate'
    end

    it "imports afterUpdate for after_update hook" do
      source = <<~RUBY
        def after_update
          sync
        end
        __END__
        <p>Test</p>
      RUBY

      result = transform(source)

      _([*result.imports[:svelte]]).must_include 'afterUpdate'
    end
  end

  describe "SvelteKit navigation integration" do
    it "imports goto when used" do
      source = <<~RUBY
        def navigate_home
          goto('/')
        end
        __END__
        <button on:click={navigateHome}>Home</button>
      RUBY

      result = transform(source)

      _([*result.imports[:sveltekitNavigation]]).must_include 'goto'
      _(result.script).must_include "import { goto } from '$app/navigation'"
    end

    it "imports page store when params is used" do
      source = <<~RUBY
        def on_mount
          id = params[:id]
        end
        __END__
        <p>Loading...</p>
      RUBY

      result = transform(source)

      _([*result.imports[:sveltekitStores]]).must_include 'page'
      _(result.script).must_include "import { page } from '$app/stores'"
    end
  end

  describe "model imports" do
    it "detects model references" do
      source = <<~RUBY
        def on_mount
          @post = Post.find(1)
        end
        __END__
        <p>{post.title}</p>
      RUBY

      result = transform(source)

      _([*result.imports[:models]]).must_include 'Post'
      _(result.script).must_include "import { Post } from '$lib/models/post'"
    end
  end

  describe "template compilation" do
    it "compiles template with snake_case to camelCase" do
      source = <<~RUBY
        @user_name = "Test"
        __END__
        <p>{user_name}</p>
      RUBY

      result = transform(source)

      _(result.template).must_include '{userName}'
    end

    it "handles {#each} blocks" do
      source = <<~RUBY
        @items = []
        __END__
        <ul>
          {#each items as item}
            <li>{item.name}</li>
          {/each}
        </ul>
      RUBY

      result = transform(source)

      _(result.template).must_include '{#each items as item}'
    end

    it "handles {#if} blocks" do
      source = <<~RUBY
        @is_loading = true
        __END__
        {#if is_loading}
          <p>Loading...</p>
        {/if}
      RUBY

      result = transform(source)

      _(result.template).must_include '{#if isLoading}'
    end
  end

  describe "methods" do
    it "detects method definitions" do
      source = <<~RUBY
        def handle_click
          puts "clicked"
        end
        __END__
        <button on:click={handleClick}>Click</button>
      RUBY

      result = transform(source)

      # Method should be converted to function in script
      _(result.script).must_include 'handleClick'
    end
  end

  describe "complete component" do
    it "transforms a full component correctly" do
      source = <<~RUBY
        @post = nil

        def on_mount
          @post = Post.find(params[:id])
        end

        def delete_post
          @post.destroy
          goto('/posts')
        end
        __END__
        {#if post}
          <article>
            <h1>{post.title}</h1>
            <button on:click={deletePost}>Delete</button>
          </article>
        {:else}
          <p>Loading...</p>
        {/if}
      RUBY

      result = transform(source)

      _(result.errors).must_be_empty

      # Check imports
      _([*result.imports[:svelte]]).must_include 'onMount'
      _([*result.imports[:sveltekitNavigation]]).must_include 'goto'
      _([*result.imports[:sveltekitStores]]).must_include 'page'
      _([*result.imports[:models]]).must_include 'Post'

      # Check component structure
      _(result.component).must_include '<script>'
      _(result.component).must_include "import { onMount } from 'svelte'"
      _(result.component).must_include "import { goto } from '$app/navigation'"
      _(result.component).must_include "import { page } from '$app/stores'"
      _(result.component).must_include "import { Post } from '$lib/models/post'"

      # Check template
      _(result.template).must_include '{#if post}'
      _(result.template).must_include '{post.title}'
      _(result.template).must_include 'on:click={deletePost}'
    end
  end

  describe "class method" do
    it "provides transform class method" do
      source = <<~RUBY
        @test = nil
        __END__
        <p>{test}</p>
      RUBY

      result = Ruby2JS::SvelteComponentTransformer.transform(source)
      _(result.component).wont_be_nil
    end
  end
end
