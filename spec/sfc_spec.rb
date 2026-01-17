require 'minitest/autorun'
require 'ruby2js/filter/sfc'
require 'ruby2js/filter/functions'

describe Ruby2JS::Filter::SFC do
  def to_js(string, template:)
    Ruby2JS.convert(string, filters: [Ruby2JS::Filter::SFC, Ruby2JS::Filter::Functions], template: template).to_s
  end

  def to_js_astro(string)
    to_js(string, template: :astro)
  end

  def to_js_svelte(string)
    to_js(string, template: :svelte)
  end

  def to_js_vue(string)
    to_js(string, template: :vue)
  end

  describe 'without template option' do
    it 'leaves instance variables unchanged' do
      result = Ruby2JS.convert('@title = "Hello"', filters: [Ruby2JS::Filter::SFC]).to_s
      _(result).must_include '_title'  # instance variable (underscore prefix)
    end
  end

  describe 'Astro (template: :astro)' do
    it 'converts @var = value to const var = value' do
      _(to_js_astro('@title = "Hello"')).must_equal 'const title = "Hello"'
    end

    it 'converts @var reference to var' do
      _(to_js_astro('puts @title')).must_equal 'console.log(title)'
    end

    it 'handles multiple instance variables' do
      result = to_js_astro('@title = "Hello"; @count = 42')
      _(result).must_include 'const title = "Hello"'
      _(result).must_include 'const count = 42'
    end

    it 'handles complex values' do
      _(to_js_astro('@items = [1, 2, 3]')).must_equal 'const items = [1, 2, 3]'
    end

    it 'handles method calls in values' do
      _(to_js_astro('@data = fetch_data()')).must_equal 'const data = fetch_data()'
    end
  end

  describe 'Svelte (template: :svelte)' do
    it 'converts @var = value to let var = value' do
      _(to_js_svelte('@title = "Hello"')).must_equal 'let title = "Hello"'
    end

    it 'converts @var reference to var' do
      _(to_js_svelte('puts @title')).must_equal 'console.log(title)'
    end

    it 'handles multiple instance variables' do
      result = to_js_svelte('@title = "Hello"; @count = 42')
      _(result).must_include 'let title = "Hello"'
      _(result).must_include 'let count = 42'
    end
  end

  describe 'Vue (template: :vue)' do
    it 'converts @var = value to const var = ref(value)' do
      _(to_js_vue('@title = "Hello"')).must_equal 'const title = ref("Hello")'
    end

    it 'converts @var reference to var' do
      _(to_js_vue('puts @title')).must_equal 'console.log(title)'
    end

    it 'handles multiple instance variables' do
      result = to_js_vue('@title = "Hello"; @count = 42')
      _(result).must_include 'const title = ref("Hello")'
      _(result).must_include 'const count = ref(42)'
    end

    it 'wraps complex values in ref()' do
      _(to_js_vue('@items = [1, 2, 3]')).must_equal 'const items = ref([1, 2, 3])'
    end
  end

  describe 'string template option' do
    it 'accepts string template option' do
      result = to_js('@title = "Hello"', template: 'astro')
      _(result).must_equal 'const title = "Hello"'
    end
  end
end
