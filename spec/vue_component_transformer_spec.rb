require 'minitest/autorun'
require 'ruby2js/vue_component_transformer'

describe Ruby2JS::VueComponentTransformer do
  def transform(source, options = {})
    Ruby2JS::VueComponentTransformer.transform(source, options)
  end

  describe "basic transformation" do
    it "transforms a simple component with template" do
      source = <<~RUBY
        @message = "Hello"
        __END__
        <h1>{{ message }}</h1>
      RUBY

      result = transform(source)

      _(result.errors).must_be_empty
      _(result.sfc).must_include '<script setup>'
      _(result.sfc).must_include '</script>'
      _(result.sfc).must_include '<template>'
      _(result.sfc).must_include '</template>'
      _(result.template).must_include '{{ message }}'
    end

    it "returns error when no template present" do
      source = "@message = 'Hello'"
      result = transform(source)

      _(result.errors).wont_be_empty
      _(result.errors.first[:type]).must_equal 'noTemplate'
    end
  end

  describe "instance variables to refs" do
    it "detects instance variable assignments" do
      source = <<~RUBY
        @count = 0
        @name = nil
        __END__
        <p>{{ count }}</p>
      RUBY

      result = transform(source)

      _([*result.imports[:vue]]).must_include 'ref'
    end

    it "converts instance variable initialization to ref" do
      source = <<~RUBY
        @post = nil
        __END__
        <p>{{ post }}</p>
      RUBY

      result = transform(source)

      _(result.script).must_include 'ref'
    end
  end

  describe "lifecycle hooks" do
    it "imports onMounted for mounted hook" do
      source = <<~RUBY
        @data = nil

        def mounted
          @data = "loaded"
        end
        __END__
        <p>{{ data }}</p>
      RUBY

      result = transform(source)

      _([*result.imports[:vue]]).must_include 'onMounted'
    end

    it "imports onUpdated for updated hook" do
      source = <<~RUBY
        def updated
          puts "updated"
        end
        __END__
        <p>Test</p>
      RUBY

      result = transform(source)

      _([*result.imports[:vue]]).must_include 'onUpdated'
    end

    it "imports onUnmounted for unmounted hook" do
      source = <<~RUBY
        def unmounted
          cleanup
        end
        __END__
        <p>Test</p>
      RUBY

      result = transform(source)

      _([*result.imports[:vue]]).must_include 'onUnmounted'
    end
  end

  describe "Vue Router integration" do
    it "imports useRouter when router is used" do
      source = <<~RUBY
        def navigate_home
          router.push('/')
        end
        __END__
        <button @click="navigateHome">Home</button>
      RUBY

      result = transform(source)

      _([*result.imports[:vueRouter]]).must_include 'useRouter'
      _(result.script).must_include "const router = useRouter()"
    end

    it "imports useRoute when params is used" do
      source = <<~RUBY
        def mounted
          id = params[:id]
        end
        __END__
        <p>Loading...</p>
      RUBY

      result = transform(source)

      _([*result.imports[:vueRouter]]).must_include 'useRoute'
      _(result.script).must_include "const route = useRoute()"
    end
  end

  describe "model imports" do
    it "detects model references" do
      source = <<~RUBY
        def mounted
          @post = Post.find(1)
        end
        __END__
        <p>{{ post.title }}</p>
      RUBY

      result = transform(source)

      _([*result.imports[:models]]).must_include 'Post'
      _(result.script).must_include "import { Post } from '@/models/post'"
    end
  end

  describe "template compilation" do
    it "compiles template with snake_case to camelCase" do
      source = <<~RUBY
        @user_name = "Test"
        __END__
        <p>{{ user_name }}</p>
      RUBY

      result = transform(source)

      _(result.template).must_include '{{ userName }}'
    end

    it "handles v-for directives" do
      source = <<~RUBY
        @items = []
        __END__
        <ul>
          <li v-for="item in items">{{ item.name }}</li>
        </ul>
      RUBY

      result = transform(source)

      _(result.template).must_include 'v-for="item in items"'
    end

    it "handles v-if directives" do
      source = <<~RUBY
        @is_loading = true
        __END__
        <p v-if="is_loading">Loading...</p>
      RUBY

      result = transform(source)

      _(result.template).must_include 'v-if="isLoading"'
    end
  end

  describe "methods" do
    it "detects method definitions" do
      source = <<~RUBY
        def handle_click
          puts "clicked"
        end
        __END__
        <button @click="handleClick">Click</button>
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

        def mounted
          @post = Post.find(params[:id])
        end

        def delete_post
          @post.destroy
          router.push('/posts')
        end
        __END__
        <article v-if="post">
          <h1>{{ post.title }}</h1>
          <button @click="deletePost">Delete</button>
        </article>
        <p v-else>Loading...</p>
      RUBY

      result = transform(source)

      _(result.errors).must_be_empty

      # Check imports
      _([*result.imports[:vue]]).must_include 'ref'
      _([*result.imports[:vue]]).must_include 'onMounted'
      _([*result.imports[:vueRouter]]).must_include 'useRouter'
      _([*result.imports[:vueRouter]]).must_include 'useRoute'
      _([*result.imports[:models]]).must_include 'Post'

      # Check SFC structure
      _(result.sfc).must_include '<script setup>'
      _(result.sfc).must_include "import { onMounted, ref } from 'vue'"
      _(result.sfc).must_include "import { useRoute, useRouter } from 'vue-router'"
      _(result.sfc).must_include "import { Post } from '@/models/post'"

      # Check template
      _(result.template).must_include 'v-if="post"'
      _(result.template).must_include '{{ post.title }}'
      _(result.template).must_include '@click="deletePost"'
    end
  end

  describe "class method" do
    it "provides transform class method" do
      source = <<~RUBY
        @test = nil
        __END__
        <p>{{ test }}</p>
      RUBY

      result = Ruby2JS::VueComponentTransformer.transform(source)
      _(result.sfc).wont_be_nil
    end
  end
end
