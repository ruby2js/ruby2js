require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'
require 'ruby2js/file_router'

describe Ruby2JS::FileRouter do
  before do
    @tmpdir = Dir.mktmpdir('ruby2js_file_router_test')
    @pages_dir = File.join(@tmpdir, 'app', 'pages')
    FileUtils.mkdir_p(@pages_dir)
  end

  after do
    FileUtils.rm_rf(@tmpdir)
  end

  def create_page(path)
    full_path = File.join(@pages_dir, path)
    FileUtils.mkdir_p(File.dirname(full_path))
    File.write(full_path, "# page: #{path}")
    full_path
  end

  describe "route discovery" do
    it "discovers index.rb as root route" do
      create_page('index.rb')
      routes = Ruby2JS::FileRouter.discover(@pages_dir)
      _(routes.length).must_equal 1
      _(routes[0][:path]).must_equal '/'
    end

    it "discovers simple page routes" do
      create_page('about.rb')
      routes = Ruby2JS::FileRouter.discover(@pages_dir)
      _(routes.length).must_equal 1
      _(routes[0][:path]).must_equal '/about'
    end

    it "discovers nested page routes" do
      create_page('blog/index.rb')
      create_page('blog/archive.rb')
      routes = Ruby2JS::FileRouter.discover(@pages_dir)
      _(routes.length).must_equal 2
      paths = routes.map { |r| r[:path] }
      _(paths).must_include '/blog'
      _(paths).must_include '/blog/archive'
    end

    it "discovers dynamic segment routes [slug]" do
      create_page('blog/[slug].rb')
      routes = Ruby2JS::FileRouter.discover(@pages_dir)
      _(routes.length).must_equal 1
      _(routes[0][:path]).must_equal '/blog/:slug'
      _(routes[0][:dynamic_segments]).must_equal [:slug]
    end

    it "discovers catch-all routes [...rest]" do
      create_page('docs/[...rest].rb')
      routes = Ruby2JS::FileRouter.discover(@pages_dir)
      _(routes.length).must_equal 1
      _(routes[0][:path]).must_equal '/docs/*rest'
      _(routes[0][:dynamic_segments]).must_equal [:"*rest"]
    end

    it "discovers multiple dynamic segments" do
      create_page('users/[user_id]/posts/[post_id].rb')
      routes = Ruby2JS::FileRouter.discover(@pages_dir)
      _(routes.length).must_equal 1
      _(routes[0][:path]).must_equal '/users/:user_id/posts/:post_id'
      _(routes[0][:dynamic_segments]).must_equal [:user_id, :post_id]
    end

    it "handles compound extensions (.jsx.rb, .vue.rb, etc.)" do
      create_page('counter.jsx.rb')
      create_page('posts/[id].vue.rb')
      create_page('users/[id].svelte.rb')
      routes = Ruby2JS::FileRouter.discover(@pages_dir)
      _(routes.length).must_equal 3
      paths = routes.map { |r| r[:path] }
      _(paths).must_include '/counter'
      _(paths).must_include '/posts/:id'
      _(paths).must_include '/users/:id'
    end

    it "ignores non-page files" do
      create_page('about.rb')
      File.write(File.join(@pages_dir, 'README.md'), '# README')
      File.write(File.join(@pages_dir, 'styles.css'), 'body {}')
      routes = Ruby2JS::FileRouter.discover(@pages_dir)
      _(routes.length).must_equal 1
      _(routes[0][:path]).must_equal '/about'
    end

    it "returns empty array for non-existent directory" do
      routes = Ruby2JS::FileRouter.discover('/nonexistent/path')
      _(routes).must_equal []
    end
  end

  describe "route sorting" do
    it "sorts static routes before dynamic routes" do
      create_page('blog/featured.rb')
      create_page('blog/[slug].rb')
      routes = Ruby2JS::FileRouter.discover(@pages_dir)
      _(routes[0][:path]).must_equal '/blog/featured'
      _(routes[1][:path]).must_equal '/blog/:slug'
    end

    it "sorts dynamic routes before catch-all routes" do
      create_page('docs/[section].rb')
      create_page('docs/[...rest].rb')
      routes = Ruby2JS::FileRouter.discover(@pages_dir)
      _(routes[0][:path]).must_equal '/docs/:section'
      _(routes[1][:path]).must_equal '/docs/*rest'
    end

    it "sorts shorter paths before longer paths" do
      create_page('a/b/c.rb')
      create_page('a/b.rb')
      create_page('a.rb')
      routes = Ruby2JS::FileRouter.discover(@pages_dir)
      _(routes[0][:path]).must_equal '/a'
      _(routes[1][:path]).must_equal '/a/b'
      _(routes[2][:path]).must_equal '/a/b/c'
    end
  end

  describe "merging with explicit routes" do
    it "includes both file-based and explicit routes" do
      create_page('about.rb')
      explicit = [{ path: '/contact', controller: 'PagesController', action: 'contact' }]

      router = Ruby2JS::FileRouter.new(@pages_dir)
      router.discover
      merged = router.merge_with(explicit)

      paths = merged.map { |r| r[:path] }
      _(paths).must_include '/about'
      _(paths).must_include '/contact'
    end

    it "explicit routes take precedence over file-based routes" do
      create_page('about.rb')
      explicit = [{ path: '/about', controller: 'CustomController', action: 'custom_about' }]

      router = Ruby2JS::FileRouter.new(@pages_dir)
      router.discover
      merged = router.merge_with(explicit)

      about_route = merged.find { |r| r[:path] == '/about' }
      _(about_route[:controller]).must_equal 'CustomController'
      _(about_route[:action]).must_equal 'custom_about'
      _(about_route[:file]).must_be_nil  # File-based route was overwritten
    end

    it "class method discover_and_merge works" do
      create_page('index.rb')
      explicit = [{ path: '/api', controller: 'ApiController', action: 'index' }]

      merged = Ruby2JS::FileRouter.discover_and_merge(@pages_dir, explicit)

      paths = merged.map { |r| r[:path] }
      _(paths).must_include '/'
      _(paths).must_include '/api'
    end
  end

  describe "file_to_route" do
    it "converts file path to route configuration" do
      router = Ruby2JS::FileRouter.new(@pages_dir)
      file = File.join(@pages_dir, 'blog', '[slug].rb')

      route = router.file_to_route(file)

      _(route[:file]).must_equal file
      _(route[:path]).must_equal '/blog/:slug'
      _(route[:dynamic_segments]).must_equal [:slug]
    end
  end
end
