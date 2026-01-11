require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'

# Load the builder for testing
$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'ruby2js/rails/builder'

describe "Unified Views Module" do
  before do
    @test_dir = Dir.mktmpdir('unified_views_test')
    @views_dir = File.join(@test_dir, 'app/views/articles')
    @dist_dir = File.join(@test_dir, 'dist')
    FileUtils.mkdir_p(@views_dir)
    FileUtils.mkdir_p(@dist_dir)
  end

  after do
    FileUtils.rm_rf(@test_dir)
  end

  describe "collect_view_files" do
    it "should collect ERB files" do
      File.write(File.join(@views_dir, 'index.html.erb'), '<h1>Index</h1>')
      File.write(File.join(@views_dir, 'show.html.erb'), '<h1>Show</h1>')

      builder = SelfhostBuilder.new(@dist_dir)
      files = builder.send(:collect_view_files, @views_dir)

      _(files.length).must_equal 2
      names = files.map { |f| f[:name] }
      _(names).must_include 'index'
      _(names).must_include 'show'
    end

    it "should collect Phlex files and convert PascalCase to snake_case" do
      File.write(File.join(@views_dir, 'Index.rb'), 'class Index < Phlex::HTML; end')
      File.write(File.join(@views_dir, 'ShowArticle.rb'), 'class ShowArticle < Phlex::HTML; end')

      builder = SelfhostBuilder.new(@dist_dir)
      files = builder.send(:collect_view_files, @views_dir)

      _(files.length).must_equal 2
      names = files.map { |f| f[:name] }
      _(names).must_include 'index'
      _(names).must_include 'show_article'
    end

    it "should collect RBX files" do
      File.write(File.join(@views_dir, 'Index.rbx'), 'def Index(); end')

      builder = SelfhostBuilder.new(@dist_dir)
      files = builder.send(:collect_view_files, @views_dir)

      _(files.length).must_equal 1
      _(files[0][:name]).must_equal 'index'
      _(files[0][:ext]).must_equal '.rbx'
    end

    it "should collect JSX/TSX files" do
      File.write(File.join(@views_dir, 'Index.jsx'), 'export default function Index() {}')
      File.write(File.join(@views_dir, 'Show.tsx'), 'export default function Show() {}')

      builder = SelfhostBuilder.new(@dist_dir)
      files = builder.send(:collect_view_files, @views_dir)

      _(files.length).must_equal 2
      exts = files.map { |f| f[:ext] }
      _(exts).must_include '.jsx'
      _(exts).must_include '.tsx'
    end

    it "should skip partials (files starting with underscore)" do
      File.write(File.join(@views_dir, 'index.html.erb'), '<h1>Index</h1>')
      File.write(File.join(@views_dir, '_partial.html.erb'), '<p>Partial</p>')
      File.write(File.join(@views_dir, '_Card.rb'), 'class Card < Phlex::HTML; end')

      builder = SelfhostBuilder.new(@dist_dir)
      files = builder.send(:collect_view_files, @views_dir)

      _(files.length).must_equal 1
      _(files[0][:name]).must_equal 'index'
    end
  end

  describe "resolve_view_conflicts" do
    it "should give Phlex priority over ERB" do
      files = [
        { name: 'index', ext: '.html.erb', path: '/path/index.html.erb', priority: 4 },
        { name: 'index', ext: '.rb', path: '/path/Index.rb', priority: 1 }
      ]

      builder = SelfhostBuilder.new(@dist_dir)
      # Capture stdout to suppress conflict messages
      result = nil
      capture_io { result = builder.send(:resolve_view_conflicts, files) }

      _(result.keys).must_equal ['index']
      _(result['index'][:ext]).must_equal '.rb'
    end

    it "should give RBX priority over ERB" do
      files = [
        { name: 'show', ext: '.html.erb', path: '/path/show.html.erb', priority: 4 },
        { name: 'show', ext: '.rbx', path: '/path/Show.rbx', priority: 2 }
      ]

      builder = SelfhostBuilder.new(@dist_dir)
      result = nil
      capture_io { result = builder.send(:resolve_view_conflicts, files) }

      _(result['show'][:ext]).must_equal '.rbx'
    end

    it "should give JSX priority over ERB but not over Phlex" do
      files = [
        { name: 'edit', ext: '.html.erb', path: '/path/edit.html.erb', priority: 4 },
        { name: 'edit', ext: '.jsx', path: '/path/Edit.jsx', priority: 3 },
        { name: 'edit', ext: '.rb', path: '/path/Edit.rb', priority: 1 }
      ]

      builder = SelfhostBuilder.new(@dist_dir)
      result = nil
      capture_io { result = builder.send(:resolve_view_conflicts, files) }

      _(result['edit'][:ext]).must_equal '.rb'
    end

    it "should keep all non-conflicting files" do
      files = [
        { name: 'index', ext: '.html.erb', path: '/path/index.html.erb', priority: 4 },
        { name: 'show', ext: '.rb', path: '/path/Show.rb', priority: 1 },
        { name: 'edit', ext: '.jsx', path: '/path/Edit.jsx', priority: 3 }
      ]

      builder = SelfhostBuilder.new(@dist_dir)
      result = builder.send(:resolve_view_conflicts, files)

      _(result.keys.sort).must_equal ['edit', 'index', 'show']
    end
  end

  describe "VIEW_FILE_PRIORITIES" do
    it "should have correct priority order" do
      priorities = SelfhostBuilder::VIEW_FILE_PRIORITIES

      # Lower number = higher priority
      _(priorities['.rb']).must_be :<, priorities['.rbx']
      _(priorities['.rbx']).must_be :<, priorities['.jsx']
      _(priorities['.jsx']).must_equal priorities['.tsx']
      _(priorities['.jsx']).must_be :<, priorities['.html.erb']
    end
  end

  describe "generate_unified_views_module" do
    it "should generate correct imports for ERB files" do
      views_by_name = {
        'index' => { name: 'index', ext: '.html.erb', path: '/path/index.html.erb', priority: 4 },
        'show' => { name: 'show', ext: '.html.erb', path: '/path/show.html.erb', priority: 4 }
      }

      views_dist_dir = File.join(@dist_dir, 'app/views')
      FileUtils.mkdir_p(views_dist_dir)

      builder = SelfhostBuilder.new(@dist_dir)
      capture_io do
        builder.send(:generate_unified_views_module, 'articles', views_by_name, views_dist_dir, ['index: ERB', 'show: ERB'])
      end

      module_path = File.join(views_dist_dir, 'articles.js')
      _(File.exist?(module_path)).must_equal true

      content = File.read(module_path)
      _(content).must_include "import { render as index_render } from './articles/index.js'"
      _(content).must_include "import { render as show_render } from './articles/show.js'"
      _(content).must_include 'export const ArticleViews'
      _(content).must_include 'index: index_render'
      _(content).must_include 'show: show_render'
    end

    it "should generate correct imports for Phlex files" do
      views_by_name = {
        'index' => { name: 'index', ext: '.rb', path: '/path/Index.rb', priority: 1 }
      }

      views_dist_dir = File.join(@dist_dir, 'app/views')
      FileUtils.mkdir_p(views_dist_dir)

      builder = SelfhostBuilder.new(@dist_dir)
      capture_io do
        builder.send(:generate_unified_views_module, 'articles', views_by_name, views_dist_dir, ['index: Phlex'])
      end

      content = File.read(File.join(views_dist_dir, 'articles.js'))
      _(content).must_include "import index_module from './articles/index.js'"
      _(content).must_include 'index: index_module.render || index_module'
    end

    it "should generate correct imports for JSX files" do
      views_by_name = {
        'dashboard' => { name: 'dashboard', ext: '.jsx', path: '/path/Dashboard.jsx', priority: 3 }
      }

      views_dist_dir = File.join(@dist_dir, 'app/views')
      FileUtils.mkdir_p(views_dist_dir)

      builder = SelfhostBuilder.new(@dist_dir)
      capture_io do
        builder.send(:generate_unified_views_module, 'admin', views_by_name, views_dist_dir, ['dashboard: JSX'])
      end

      content = File.read(File.join(views_dist_dir, 'admin.js'))
      _(content).must_include "import dashboard_component from './admin/dashboard.js'"
      _(content).must_include 'dashboard: dashboard_component'
    end

    it "should handle mixed file types in one module" do
      views_by_name = {
        'index' => { name: 'index', ext: '.html.erb', path: '/path/index.html.erb', priority: 4 },
        'show' => { name: 'show', ext: '.rb', path: '/path/Show.rb', priority: 1 },
        'edit' => { name: 'edit', ext: '.jsx', path: '/path/Edit.jsx', priority: 3 }
      }

      views_dist_dir = File.join(@dist_dir, 'app/views')
      FileUtils.mkdir_p(views_dist_dir)

      builder = SelfhostBuilder.new(@dist_dir)
      capture_io do
        builder.send(:generate_unified_views_module, 'posts', views_by_name, views_dist_dir, ['edit: JSX', 'index: ERB', 'show: Phlex'])
      end

      content = File.read(File.join(views_dist_dir, 'posts.js'))

      # Check file types comment
      _(content).must_include 'File types:'

      # Check all import styles
      _(content).must_include "import { render as index_render }"  # ERB
      _(content).must_include "import show_module"                  # Phlex
      _(content).must_include "import edit_component"               # JSX
    end

    it "should handle 'new' reserved word with $new alias" do
      views_by_name = {
        'new' => { name: 'new', ext: '.html.erb', path: '/path/new.html.erb', priority: 4 }
      }

      views_dist_dir = File.join(@dist_dir, 'app/views')
      FileUtils.mkdir_p(views_dist_dir)

      builder = SelfhostBuilder.new(@dist_dir)
      capture_io do
        builder.send(:generate_unified_views_module, 'articles', views_by_name, views_dist_dir, ['new: ERB'])
      end

      content = File.read(File.join(views_dist_dir, 'articles.js'))
      _(content).must_include '$new: new_render'
      _(content).must_include "// $new alias for 'new'"
    end
  end
end
