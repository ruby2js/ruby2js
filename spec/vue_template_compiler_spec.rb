require 'minitest/autorun'
require 'ruby2js/vue_template_compiler'

describe Ruby2JS::VueTemplateCompiler do
  def compile(template, options = {})
    Ruby2JS::VueTemplateCompiler.compile(template, options)
  end

  describe "interpolations {{ }}" do
    it "converts simple variable references" do
      result = compile('<h1>{{ title }}</h1>')
      _(result.template).must_equal '<h1>{{ title }}</h1>'
      _(result.errors).must_be_empty
    end

    it "converts property access" do
      result = compile('<span>{{ post.title }}</span>')
      _(result.template).must_equal '<span>{{ post.title }}</span>'
    end

    it "converts snake_case to camelCase" do
      result = compile('<span>{{ user_name }}</span>')
      _(result.template).must_equal '<span>{{ userName }}</span>'
    end

    it "converts method calls" do
      result = compile('<span>{{ items.length }}</span>')
      _(result.template).must_equal '<span>{{ items.length }}</span>'
    end

    it "converts Ruby methods to JS equivalents" do
      result = compile('<span>{{ items.map { |i| i.name } }}</span>')
      _(result.template).must_equal '<span>{{ items.map(i => i.name) }}</span>'
    end

    it "handles multiple interpolations" do
      result = compile('<p>{{ first_name }} {{ last_name }}</p>')
      _(result.template).must_equal '<p>{{ firstName }} {{ lastName }}</p>'
    end

    it "handles interpolations with whitespace" do
      result = compile('<p>{{   spaced_var   }}</p>')
      _(result.template).must_equal '<p>{{ spacedVar }}</p>'
    end

    it "handles ternary expressions" do
      result = compile('<span>{{ is_active ? "Yes" : "No" }}</span>')
      _(result.template).must_equal '<span>{{ isActive ? "Yes" : "No" }}</span>'
    end
  end

  describe "v-for directive" do
    it "converts simple v-for" do
      result = compile('<li v-for="item in items">{{ item }}</li>')
      _(result.template).must_equal '<li v-for="item in items">{{ item }}</li>'
    end

    it "converts v-for with snake_case collection" do
      result = compile('<li v-for="post in blog_posts">{{ post.title }}</li>')
      _(result.template).must_equal '<li v-for="post in blogPosts">{{ post.title }}</li>'
    end

    it "converts v-for with index" do
      result = compile('<li v-for="(item, index) in items">{{ index }}: {{ item }}</li>')
      _(result.template).must_equal '<li v-for="(item, index) in items">{{ index }}: {{ item }}</li>'
    end

    it "converts v-for with property access" do
      result = compile('<li v-for="item in user.items">{{ item }}</li>')
      _(result.template).must_equal '<li v-for="item in user.items">{{ item }}</li>'
    end

    it "handles v-for with :key binding" do
      result = compile('<li v-for="item in items" :key="item.id">{{ item.name }}</li>')
      _(result.template).must_equal '<li v-for="item in items" :key="item.id">{{ item.name }}</li>'
    end
  end

  describe "v-if/v-else-if/v-show directives" do
    it "converts v-if with simple condition" do
      result = compile('<p v-if="show">Visible</p>')
      _(result.template).must_equal '<p v-if="show">Visible</p>'
    end

    it "converts v-if with snake_case variable" do
      result = compile('<p v-if="is_visible">Visible</p>')
      _(result.template).must_equal '<p v-if="isVisible">Visible</p>'
    end

    it "converts v-if with comparison" do
      result = compile('<p v-if="count > 0">Has items</p>')
      _(result.template).must_equal '<p v-if="count > 0">Has items</p>'
    end

    it "converts v-else-if" do
      result = compile('<p v-else-if="other_condition">Alternative</p>')
      _(result.template).must_equal '<p v-else-if="otherCondition">Alternative</p>'
    end

    it "converts v-show" do
      result = compile('<p v-show="is_expanded">Details</p>')
      _(result.template).must_equal '<p v-show="isExpanded">Details</p>'
    end

    it "handles negation" do
      result = compile('<p v-if="!is_loading">Loaded</p>')
      _(result.template).must_equal '<p v-if="!isLoading">Loaded</p>'
    end
  end

  describe ":prop bindings (v-bind shorthand)" do
    it "converts :prop with simple value" do
      result = compile('<img :src="image_url">')
      _(result.template).must_equal '<img :src="imageUrl">'
    end

    it "converts :prop with property access" do
      result = compile('<a :href="post.url">{{ post.title }}</a>')
      _(result.template).must_equal '<a :href="post.url">{{ post.title }}</a>'
    end

    it "converts :class with object syntax" do
      result = compile('<div :class="{ active: is_active }"></div>')
      # Note: Ruby2JS may format object literals without spaces
      _(result.template).must_match /:class="\{active: isActive\}"/
    end

    it "converts :style binding" do
      result = compile('<div :style="{ color: text_color }"></div>')
      # Note: Ruby2JS may format object literals without spaces
      _(result.template).must_match /:style="\{color: textColor\}"/
    end

    it "does not modify event handlers (@click)" do
      result = compile('<button @click="handleClick">Click</button>')
      _(result.template).must_equal '<button @click="handleClick">Click</button>'
    end

    it "handles multiple bindings" do
      result = compile('<input :value="input_value" :disabled="is_disabled">')
      _(result.template).must_equal '<input :value="inputValue" :disabled="isDisabled">'
    end
  end

  describe "v-bind:prop full syntax" do
    it "converts v-bind:prop" do
      result = compile('<img v-bind:src="image_url">')
      _(result.template).must_equal '<img v-bind:src="imageUrl">'
    end
  end

  describe "v-model directive" do
    it "converts v-model with simple ref" do
      result = compile('<input v-model="user_input">')
      _(result.template).must_equal '<input v-model="userInput">'
    end

    it "converts v-model with property access" do
      result = compile('<input v-model="form.email">')
      _(result.template).must_equal '<input v-model="form.email">'
    end
  end

  describe "complex templates" do
    it "handles a full component template" do
      template = <<~VUE
        <div>
          <h1>{{ page_title }}</h1>
          <ul v-if="items.length > 0">
            <li v-for="item in filtered_items" :key="item.id">
              {{ item.display_name }}
            </li>
          </ul>
          <p v-else>No items found</p>
          <button @click="loadMore" :disabled="is_loading">
            {{ is_loading ? "Loading..." : "Load More" }}
          </button>
        </div>
      VUE

      result = compile(template)

      _(result.template).must_include '{{ pageTitle }}'
      _(result.template).must_include 'v-for="item in filteredItems"'
      _(result.template).must_include ':disabled="isLoading"'
      _(result.template).must_include '{{ isLoading ? "Loading..." : "Load More" }}'
      _(result.template).must_include '@click="loadMore"'  # Unchanged
      _(result.errors).must_be_empty
    end
  end

  describe "error handling" do
    it "reports errors but continues processing" do
      # Invalid Ruby syntax in one interpolation
      result = compile('<p>{{ valid_var }}</p><p>{{ def }}</p>')
      # Should still process valid parts
      _(result.template).must_include '{{ validVar }}'
    end
  end

  describe "options" do
    it "respects camelCase: false option" do
      result = compile('<span>{{ user_name }}</span>', camelCase: false)
      _(result.template).must_equal '<span>{{ user_name }}</span>'
    end
  end

  describe "class method" do
    it "provides compile class method" do
      result = Ruby2JS::VueTemplateCompiler.compile('<p>{{ test_var }}</p>')
      _(result.template).must_equal '<p>{{ testVar }}</p>'
    end
  end
end
