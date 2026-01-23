#!/usr/bin/env ruby
# Test the ErbToJsx converter against blog templates

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'ruby2js'
require 'ruby2js/erb_to_jsx'

# Test templates from the Astro blog demo
TEMPLATES = {
  # Simple output
  simple_output: {
    input: '<p><%= article.title %></p>',
    expected_pattern: /<p>\{article\.title\}<\/p>/
  },

  # Simple if
  simple_if: {
    input: '<% if loading %><p>Loading...</p><% end %>',
    expected_pattern: /\{\(loading\) && \(<p>Loading\.\.\.<\/p>\)\}/
  },

  # If/else
  if_else: {
    input: '<% if loading %><p>Loading</p><% else %><p>Done</p><% end %>',
    expected_pattern: /\{\(loading\) \? \(<p>Loading<\/p>\) : \(<p>Done<\/p>\)\}/
  },

  # Unless
  simple_unless: {
    input: '<% unless loading %><p>Ready</p><% end %>',
    expected_pattern: /\{!\(loading\) && \(<p>Ready<\/p>\)\}/
  },

  # Each loop
  each_loop: {
    input: '<% articles.each do |article| %><p><%= article.title %></p><% end %>',
    expected_pattern: /\{articles\.map\(article => \(<p>\{article\.title\}<\/p>\)\)\}/
  },

  # Attribute with expression
  attr_expr: {
    input: '<a href={"/articles/" + article.id}>Link</a>',
    expected_pattern: /<a href=\{"\/articles\/" \+ article\.id\}>Link<\/a>/
  },

  # Style object (double braces)
  style_object: {
    input: '<h2 style={{marginTop: 0}}>Title</h2>',
    expected_pattern: /<h2 style=\{\{marginTop: 0\}\}>Title<\/h2>/
  },

  # Self-closing element
  self_closing: {
    input: '<input type="text" value={title} />',
    expected_pattern: /<input type="text" value=\{title\} \/>/
  },

  # Void element (no explicit close)
  void_element: {
    input: '<input type="text" value={title}>',
    expected_pattern: /<input type="text" value=\{title\} \/>/
  },

  # Class to className conversion
  class_to_classname: {
    input: '<p class="meta">Text</p>',
    expected_pattern: /<p className="meta">Text<\/p>/
  },

  # Lambda in attribute (Ruby syntax)
  lambda_attr: {
    input: '<button onClick={-> { handleClick() }}>Click</button>',
    expected_pattern: /<button onClick=\{.*handleClick.*\}>Click<\/button>/
  },

  # Lambda with param
  lambda_with_param: {
    input: '<button onClick={->(e) { handleClick(e) }}>Click</button>',
    expected_pattern: /<button onClick=\{.*handleClick.*\}>Click<\/button>/
  },

  # Ternary in content
  ternary_content: {
    input: '<span>{saving ? "Saving..." : "Save"}</span>',
    expected_pattern: /<span>\{saving \? "Saving\.\.\." : "Save"\}<\/span>/
  },

  # Nested elements
  nested_elements: {
    input: '<div class="card"><h2><%= title %></h2><p><%= body %></p></div>',
    expected_pattern: /<div className="card"><h2>\{title\}<\/h2><p>\{body\}<\/p><\/div>/
  },

  # Multiple top-level conditions (blog pattern)
  multiple_conditions: {
    input: <<~ERB,
      <div>
        <% if loading %>
          <p>Loading...</p>
        <% end %>
        <% if !loading && items.length == 0 %>
          <p>No items</p>
        <% end %>
        <% if !loading && items.length > 0 %>
          <p>Has items</p>
        <% end %>
      </div>
    ERB
    expected_pattern: /loading.*&&.*Loading.*!.*loading.*items\.length.*==.*0.*No items/m
  }
}

# Run tests
puts "Testing ErbToJsx converter"
puts "=" * 50

passed = 0
failed = 0

TEMPLATES.each do |name, test|
  begin
    result = Ruby2JS::ErbToJsx.convert(test[:input])

    if result =~ test[:expected_pattern]
      puts "✓ #{name}"
      passed += 1
    else
      puts "✗ #{name}"
      puts "  Input:    #{test[:input].inspect}"
      puts "  Output:   #{result.inspect}"
      puts "  Expected: #{test[:expected_pattern].inspect}"
      failed += 1
    end
  rescue => e
    puts "✗ #{name} (ERROR)"
    puts "  Input: #{test[:input].inspect}"
    puts "  Error: #{e.message}"
    puts "  #{e.backtrace.first(3).join("\n  ")}"
    failed += 1
  end
end

puts "=" * 50
puts "Results: #{passed} passed, #{failed} failed"
exit(failed > 0 ? 1 : 0)
