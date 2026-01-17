require 'minitest/autorun'
require 'ruby2js/astro_component_transformer'

describe Ruby2JS::AstroComponentTransformer do
  def transform(source, options = {})
    Ruby2JS::AstroComponentTransformer.transform(source, options)
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
      _(result.component).must_include '---'
      _(result.template).must_include '{message}'
    end

    it "returns error when no template present" do
      source = "@message = 'Hello'"
      result = transform(source)

      _(result.errors).wont_be_empty
      _(result.errors.first[:type]).must_equal 'noTemplate'
    end

    it "handles component with minimal frontmatter" do
      source = <<~RUBY
        # Static component
        __END__
        <h1>Static Content</h1>
      RUBY

      result = transform(source)

      _(result.errors).must_be_empty
      _(result.template).must_include '<h1>Static Content</h1>'
    end
  end

  describe "instance variables to const declarations" do
    it "detects instance variable assignments" do
      source = <<~RUBY
        @count = 0
        @name = nil
        __END__
        <p>{count}</p>
      RUBY

      result = transform(source)

      # Astro uses const declarations
      _(result.frontmatter).must_include 'count'
    end
  end

  describe "params access" do
    it "transforms params[:id] to Astro.params" do
      source = <<~RUBY
        @id = params[:id]
        __END__
        <p>ID: {id}</p>
      RUBY

      result = transform(source)

      _(result.frontmatter).must_include 'Astro.params'
    end

    it "destructures specific params" do
      source = <<~RUBY
        @slug = params[:slug]
        __END__
        <p>{slug}</p>
      RUBY

      result = transform(source)

      _(result.frontmatter).must_include 'const { slug } = Astro.params'
    end
  end

  describe "model imports" do
    it "detects model references" do
      source = <<~RUBY
        @post = Post.find(1)
        __END__
        <p>{post.title}</p>
      RUBY

      result = transform(source)

      _([*result.imports[:models]]).must_include 'Post'
      _(result.frontmatter).must_include "import { Post } from '../models/post'"
    end

    it "handles multiple model references" do
      source = <<~RUBY
        @post = Post.find(1)
        @comments = Comment.where(post_id: 1)
        __END__
        <p>{post.title}</p>
      RUBY

      result = transform(source)

      _([*result.imports[:models]]).must_include 'Post'
      _([*result.imports[:models]]).must_include 'Comment'
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

    it "handles component props" do
      source = <<~RUBY
        @items = []
        __END__
        <ItemList items={items} show_count={true} />
      RUBY

      result = transform(source)

      _(result.template).must_include 'items={items}'
      _(result.template).must_include 'showCount={true}'
    end

    it "preserves client directives" do
      source = <<~RUBY
        @count = 0
        __END__
        <Counter initial={count} client:load />
      RUBY

      result = transform(source)

      _(result.template).must_include 'client:load'
    end
  end

  describe "methods" do
    it "detects method definitions" do
      source = <<~RUBY
        def format_date(date)
          date.strftime("%Y-%m-%d")
        end
        __END__
        <p>{format_date(post.created_at)}</p>
      RUBY

      result = transform(source)

      # Method should be converted to function in frontmatter
      _(result.frontmatter).must_include 'formatDate'
    end
  end

  describe "complete component" do
    it "transforms a full component correctly" do
      source = <<~RUBY
        @post = nil
        @post = Post.find(params[:id])
        @comments = @post.comments
        __END__
        <Layout title={post.title}>
          <article>
            <h1>{post.title}</h1>
            <div set:html={post.body} />
          </article>
          <section>
            <h2>Comments</h2>
            {comments.map { |comment|
              <Comment comment={comment} />
            }}
          </section>
        </Layout>
      RUBY

      result = transform(source)

      _(result.errors).must_be_empty

      # Check imports
      _([*result.imports[:models]]).must_include 'Post'

      # Check component structure
      _(result.component).must_include '---'
      _(result.component).must_include "import { Post } from '../models/post'"
      _(result.component).must_include 'Astro.params'

      # Check template
      _(result.template).must_include 'title={post.title}'
      _(result.template).must_include '{post.title}'
      _(result.template).must_include 'set:html={post.body}'
      _(result.template).must_include 'comments.map'
    end
  end

  describe "Layout component pattern" do
    it "handles Layout with props" do
      source = <<~RUBY
        @title = "My Page"
        @description = "Page description"
        __END__
        <Layout title={title} description={description}>
          <main>
            <h1>{title}</h1>
          </main>
        </Layout>
      RUBY

      result = transform(source)

      _(result.template).must_include '<Layout title={title} description={description}>'
      _(result.template).must_include '<main>'
    end
  end

  describe "slots" do
    it "handles named slots" do
      source = <<~RUBY
        @sidebar_content = "Sidebar"
        __END__
        <Layout>
          <div slot="sidebar">{sidebar_content}</div>
          <main>Main content</main>
        </Layout>
      RUBY

      result = transform(source)

      _(result.template).must_include 'slot="sidebar"'
      _(result.template).must_include '{sidebarContent}'
    end
  end

  describe "class method" do
    it "provides transform class method" do
      source = <<~RUBY
        @test = nil
        __END__
        <p>{test}</p>
      RUBY

      result = Ruby2JS::AstroComponentTransformer.transform(source)
      _(result.component).wont_be_nil
    end
  end
end
