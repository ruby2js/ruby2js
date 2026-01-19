require 'minitest/autorun'
require 'ruby2js/erb_pnode_transformer'

describe Ruby2JS::ErbPnodeTransformer do
  def transform(source, options = {})
    Ruby2JS::ErbPnodeTransformer.transform(source, options)
  end

  describe "basic transformation" do
    it "transforms a simple component with template" do
      source = <<~RUBY
        def Hello()
          render
        end
        __END__
        <h1>Hello World</h1>
      RUBY

      result = transform(source)

      _(result.errors).must_be_empty
      _(result.component).must_include 'function Hello()'
      _(result.component).must_include '<h1>Hello World</h1>'
    end

    it "returns error when no template present" do
      source = "def Hello(); end"
      result = transform(source)

      _(result.errors).wont_be_empty
      _(result.errors.first[:type]).must_equal 'noTemplate'
    end
  end

  describe "ERB output expressions" do
    it "converts <%= expr %> to {expr}" do
      source = <<~RUBY
        def Greeting()
          name = "World"
          render
        end
        __END__
        <h1>Hello <%= name %></h1>
      RUBY

      result = transform(source)

      _(result.errors).must_be_empty
      _(result.component).must_include '{name}'
    end

    it "handles complex expressions" do
      source = <<~RUBY
        def Counter()
          count = 5
          render
        end
        __END__
        <p>Count: <%= count * 2 %></p>
      RUBY

      result = transform(source)

      _(result.errors).must_be_empty
      _(result.component).must_include '{count * 2}'
    end
  end

  describe "ERB conditionals" do
    it "converts if/else to ternary" do
      source = <<~RUBY
        def Status()
          loading = true
          render
        end
        __END__
        <% if loading %>
          <p>Loading...</p>
        <% else %>
          <p>Done</p>
        <% end %>
      RUBY

      result = transform(source)

      _(result.errors).must_be_empty
      # The JSX should have conditional logic
      _(result.component).must_include 'loading'
      _(result.component).must_include 'Loading...'
      _(result.component).must_include 'Done'
    end

    it "converts if without else" do
      source = <<~RUBY
        def Notice()
          show = true
          render
        end
        __END__
        <% if show %>
          <p>Notice!</p>
        <% end %>
      RUBY

      result = transform(source)

      _(result.errors).must_be_empty
      _(result.component).must_include 'show'
      _(result.component).must_include 'Notice!'
    end

    it "converts unless to negated conditional" do
      source = <<~RUBY
        def Notice()
          hidden = false
          render
        end
        __END__
        <% unless hidden %>
          <p>Visible</p>
        <% end %>
      RUBY

      result = transform(source)

      _(result.errors).must_be_empty
      _(result.component).must_include 'hidden'
      _(result.component).must_include 'Visible'
    end
  end

  describe "ERB loops" do
    it "converts each to map" do
      source = <<~RUBY
        def ItemList()
          items = ["a", "b", "c"]
          render
        end
        __END__
        <ul>
          <% items.each do |item| %>
            <li><%= item %></li>
          <% end %>
        </ul>
      RUBY

      result = transform(source)

      _(result.errors).must_be_empty
      _(result.component).must_include '.map('
      _(result.component).must_include 'item =>'
    end

    it "handles nested loops" do
      source = <<~RUBY
        def Grid()
          rows = [[1, 2], [3, 4]]
          render
        end
        __END__
        <% rows.each do |row| %>
          <div>
            <% row.each do |cell| %>
              <span><%= cell %></span>
            <% end %>
          </div>
        <% end %>
      RUBY

      result = transform(source)

      _(result.errors).must_be_empty
      # Should have two .map() calls
      _(result.component.scan('.map(').length).must_be :>=, 2
    end
  end

  describe "JSX attributes" do
    it "preserves static attributes" do
      source = <<~RUBY
        def Card()
          render
        end
        __END__
        <div class="card" id="main">Content</div>
      RUBY

      result = transform(source)

      _(result.errors).must_be_empty
      # class should be converted to className
      _(result.component).must_include 'className="card"'
    end

    it "handles dynamic attributes" do
      source = <<~RUBY
        def Button()
          disabled = true
          render
        end
        __END__
        <button disabled={disabled}>Click</button>
      RUBY

      result = transform(source)

      _(result.errors).must_be_empty
      _(result.component).must_include 'disabled={disabled}'
    end

    it "handles key attribute" do
      source = <<~RUBY
        def List()
          items = [{id: 1}, {id: 2}]
          render
        end
        __END__
        <% items.each do |item| %>
          <div key={item.id}><%= item.id %></div>
        <% end %>
      RUBY

      result = transform(source)

      _(result.errors).must_be_empty
      _(result.component).must_include 'key={item.id}'
    end
  end

  describe "void elements" do
    it "handles self-closing void elements" do
      source = <<~RUBY
        def Image()
          render
        end
        __END__
        <img src="photo.jpg">
        <br>
        <input type="text">
      RUBY

      result = transform(source)

      _(result.errors).must_be_empty
      # Void elements should be self-closing in JSX
      _(result.component).must_include '<img'
      _(result.component).must_include '<br'
      _(result.component).must_include '<input'
    end
  end

  describe "Preact imports" do
    it "uses Preact by default" do
      source = <<~RUBY
        def Component()
          render
        end
        __END__
        <div>Test</div>
      RUBY

      result = transform(source)

      # Should import from Preact (via React filter)
      _(result.component).must_include 'import'
    end
  end

  describe "complex component" do
    it "transforms a full Preact component" do
      source = <<~RUBY
        import ["useState", "useEffect"], from: "preact/hooks"

        def PostList()
          posts, setPosts = useState([])
          loading, setLoading = useState(true)

          render
        end

        export default PostList
        __END__
        <% if loading %>
          <div class="loading">Loading...</div>
        <% else %>
          <div class="posts">
            <% posts.each do |post| %>
              <article key={post.id}>
                <h2><%= post.title %></h2>
              </article>
            <% end %>
          </div>
        <% end %>
      RUBY

      result = transform(source)

      _(result.errors).must_be_empty
      _(result.component).must_include 'function PostList()'
      _(result.component).must_include 'useState'
      _(result.component).must_include 'loading'
      _(result.component).must_include 'posts.map'
      _(result.component).must_include 'export default PostList'
    end
  end
end
