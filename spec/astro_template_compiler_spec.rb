require 'minitest/autorun'
require 'ruby2js/astro_template_compiler'

describe Ruby2JS::AstroTemplateCompiler do
  def compile(template, options = {})
    Ruby2JS::AstroTemplateCompiler.compile(template, options)
  end

  describe "interpolations { }" do
    it "converts simple variable references" do
      result = compile('<h1>{title}</h1>')
      _(result.template).must_equal '<h1>{title}</h1>'
      _(result.errors).must_be_empty
    end

    it "converts property access" do
      result = compile('<span>{post.title}</span>')
      _(result.template).must_equal '<span>{post.title}</span>'
    end

    it "converts snake_case to camelCase" do
      result = compile('<span>{user_name}</span>')
      _(result.template).must_equal '<span>{userName}</span>'
    end

    it "converts method calls" do
      result = compile('<span>{items.length}</span>')
      _(result.template).must_equal '<span>{items.length}</span>'
    end

    it "handles multiple interpolations" do
      result = compile('<p>{first_name} {last_name}</p>')
      _(result.template).must_equal '<p>{firstName} {lastName}</p>'
    end

    it "handles interpolations with whitespace" do
      result = compile('<p>{  spaced_var  }</p>')
      _(result.template).must_equal '<p>{spacedVar}</p>'
    end

    it "handles ternary expressions" do
      result = compile('<span>{is_active ? "Yes" : "No"}</span>')
      _(result.template).must_equal '<span>{isActive ? "Yes" : "No"}</span>'
    end

    it "handles nested braces in strings" do
      result = compile('<span>{"hello {world}"}</span>')
      _(result.template).must_equal '<span>{"hello {world}"}</span>'
    end
  end

  describe "Ruby blocks with JSX" do
    it "converts .map with JSX body to arrow function" do
      result = compile('{items.map { |item| <li>{item.name}</li> }}')
      _(result.template).must_equal '{items.map(item => <li>{item.name}</li>)}'
    end

    it "converts .each with JSX body to .map arrow function" do
      result = compile('{items.each { |item| <li>{item.name}</li> }}')
      _(result.template).must_equal '{items.map(item => <li>{item.name}</li>)}'
    end

    it "handles snake_case in collection and block body" do
      result = compile('{blog_posts.map { |post| <li>{post.display_title}</li> }}')
      _(result.template).must_equal '{blogPosts.map(post => <li>{post.displayTitle}</li>)}'
    end

    it "handles index parameter" do
      result = compile('{items.map { |item, idx| <li>{idx}: {item.name}</li> }}')
      _(result.template).must_include 'items.map(item, idx =>'
    end

    it "handles nested JSX elements" do
      result = compile('{posts.map { |post| <article><h2>{post.title}</h2><p>{post.excerpt}</p></article> }}')
      _(result.template).must_include 'posts.map(post => <article>'
      _(result.template).must_include '{post.title}'
      _(result.template).must_include '{post.excerpt}'
    end

    it "handles .select/.filter with expression" do
      result = compile('{items.select { |item| item.active }}')
      _(result.template).must_equal '{items.filter(item => item.active)}'
    end

    it "handles chained methods" do
      result = compile('{visible_items.select { |i| i.active }.length}')
      _(result.template).must_include 'visibleItems.filter'
    end
  end

  describe "array methods (simple expressions)" do
    it "converts .map with simple block" do
      result = compile('{items.map { |item| item.name }}')
      _(result.template).must_include 'items.map'
    end

    it "converts .find with block" do
      result = compile('{items.find { |item| item.id == target_id }}')
      _(result.template).must_include 'items.find'
    end
  end

  describe "spread operator" do
    it "converts spread with snake_case" do
      result = compile('<Component {...spread_props} />')
      _(result.template).must_equal '<Component {...spreadProps} />'
    end

    it "handles spread with property access" do
      result = compile('<div {...item.attrs}></div>')
      _(result.template).must_equal '<div {...item.attrs}></div>'
    end
  end

  describe "component props" do
    it "preserves static string props" do
      result = compile('<Button label="Click me" />')
      _(result.template).must_equal '<Button label="Click me" />'
    end

    it "converts dynamic props with snake_case" do
      result = compile('<Card title={post_title} />')
      _(result.template).must_equal '<Card title={postTitle} />'
    end

    it "preserves Astro client directives" do
      result = compile('<Counter client:load initial={start_value} />')
      _(result.template).must_equal '<Counter client:load initial={startValue} />'
    end

    it "preserves client:visible directive" do
      result = compile('<HeavyComponent client:visible />')
      _(result.template).must_equal '<HeavyComponent client:visible />'
    end

    it "preserves client:only directive with framework" do
      result = compile('<ReactChart client:only="react" />')
      _(result.template).must_equal '<ReactChart client:only="react" />'
    end
  end

  describe "Astro-specific attributes" do
    it "preserves set:html directive" do
      result = compile('<div set:html={raw_content} />')
      _(result.template).must_equal '<div set:html={rawContent} />'
    end

    it "preserves set:text directive" do
      result = compile('<span set:text={safe_text} />')
      _(result.template).must_equal '<span set:text={safeText} />'
    end

    it "preserves is:raw directive" do
      result = compile('<pre is:raw>{code_block}</pre>')
      _(result.template).must_include 'is:raw'
    end
  end

  describe "complex templates" do
    it "handles a full component template with Ruby blocks" do
      # Ruby block syntax gets converted to JavaScript arrow functions
      template = <<~ASTRO
        <Layout title={page_title}>
          <header>
            <h1>{page_title}</h1>
          </header>
          <main>
            <ul>
              {filtered_items.map { |item| <li>{item.display_name}</li> }}
            </ul>
            <button disabled={is_loading}>
              {is_loading ? "Loading..." : "Load More"}
            </button>
          </main>
        </Layout>
      ASTRO

      result = compile(template)

      _(result.template).must_include 'title={pageTitle}'
      _(result.template).must_include '{pageTitle}'
      _(result.template).must_include 'filteredItems.map(item =>'
      _(result.template).must_include 'item.displayName'
      _(result.template).must_include 'disabled={isLoading}'
      _(result.template).must_include '{isLoading ? "Loading..." : "Load More"}'
      _(result.errors).must_be_empty
    end

    it "handles slots" do
      result = compile('<slot name="header" />')
      _(result.template).must_equal '<slot name="header" />'
    end

    it "handles named slots with content" do
      result = compile('<div slot="sidebar">{sidebar_content}</div>')
      _(result.template).must_equal '<div slot="sidebar">{sidebarContent}</div>'
    end
  end

  describe "options" do
    it "respects camelCase: false option" do
      result = compile('<span>{user_name}</span>', camelCase: false)
      _(result.template).must_equal '<span>{user_name}</span>'
    end
  end

  describe "class method" do
    it "provides compile class method" do
      result = Ruby2JS::AstroTemplateCompiler.compile('<p>{test_var}</p>')
      _(result.template).must_equal '<p>{testVar}</p>'
    end
  end

  describe "error handling" do
    it "handles unmatched braces gracefully" do
      result = compile('<p>{unclosed')
      _(result.errors).wont_be_empty
      _(result.errors.first[:type]).must_equal :unmatched_brace
    end
  end
end
