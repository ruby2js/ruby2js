import { test, describe, before } from 'node:test';
import assert from 'node:assert';
import { compileLiquid, convertExpression } from '../src/liquid.js';
import { initPrism } from 'ruby2js';

// Initialize Prism before all tests
before(async () => {
  await initPrism();
});

describe('convertExpression', () => {
  test('converts simple method call', () => {
    const result = convertExpression('post.title');
    assert.strictEqual(result, 'post.title');
  });

  test('converts snake_case to camelCase', () => {
    const result = convertExpression('post.published_at');
    assert.strictEqual(result, 'post.publishedAt');
  });

  test('passes through strftime (complex date formatting preserved)', () => {
    // strftime is complex and may not be auto-converted by Functions filter
    // In practice, Liquid has its own date filter for formatting
    const result = convertExpression('post.date.strftime("%B %d, %Y")');
    assert.ok(result.includes('strftime'));
  });

  test('converts negation', () => {
    const result = convertExpression('!post.draft');
    assert.strictEqual(result, '!post.draft');
  });

  test('converts comparison', () => {
    const result = convertExpression('count > 0');
    assert.strictEqual(result, 'count > 0');
  });

  test('converts method chain', () => {
    const result = convertExpression('posts.select { |p| !p.draft }');
    assert.ok(result.includes('filter'));
  });
});

describe('compileLiquid interpolations', () => {
  test('compiles simple interpolation', async () => {
    const result = await compileLiquid('{{ post.title }}');
    assert.strictEqual(result.template, '{{ post.title }}');
    assert.strictEqual(result.errors.length, 0);
  });

  test('compiles snake_case interpolation', async () => {
    const result = await compileLiquid('{{ post.published_at }}');
    assert.strictEqual(result.template, '{{ post.publishedAt }}');
  });

  test('preserves Liquid filters', async () => {
    const result = await compileLiquid('{{ post.title | escape }}');
    assert.strictEqual(result.template, '{{ post.title | escape }}');
  });

  test('compiles expression with Liquid filters', async () => {
    const result = await compileLiquid('{{ post.published_at | date: "%B %d" }}');
    assert.strictEqual(result.template, '{{ post.publishedAt | date: "%B %d" }}');
  });

  test('compiles multiple interpolations', async () => {
    const result = await compileLiquid('<h1>{{ post.title }}</h1><p>{{ post.body_text }}</p>');
    assert.strictEqual(result.template, '<h1>{{ post.title }}</h1><p>{{ post.bodyText }}</p>');
  });
});

describe('compileLiquid for loops', () => {
  test('compiles simple for loop', async () => {
    const result = await compileLiquid('{% for post in posts %}');
    assert.strictEqual(result.template, '{% for post in posts %}');
  });

  test('compiles for loop with method chain', async () => {
    const result = await compileLiquid('{% for post in published_posts %}');
    assert.strictEqual(result.template, '{% for post in publishedPosts %}');
  });

  test('preserves for loop parameters', async () => {
    const result = await compileLiquid('{% for post in posts limit:5 offset:2 %}');
    assert.strictEqual(result.template, '{% for post in posts limit:5 offset:2 %}');
  });

  test('compiles for loop with reversed', async () => {
    const result = await compileLiquid('{% for post in posts reversed %}');
    assert.strictEqual(result.template, '{% for post in posts reversed %}');
  });
});

describe('compileLiquid conditionals', () => {
  test('compiles if statement', async () => {
    const result = await compileLiquid('{% if post.draft %}');
    assert.strictEqual(result.template, '{% if post.draft %}');
  });

  test('compiles if with negation', async () => {
    const result = await compileLiquid('{% if !post.draft %}');
    assert.strictEqual(result.template, '{% if !post.draft %}');
  });

  test('compiles elsif', async () => {
    const result = await compileLiquid('{% elsif post.featured %}');
    assert.strictEqual(result.template, '{% elsif post.featured %}');
  });

  test('compiles unless', async () => {
    const result = await compileLiquid('{% unless post.hidden %}');
    assert.strictEqual(result.template, '{% unless post.hidden %}');
  });

  test('compiles comparison condition', async () => {
    const result = await compileLiquid('{% if posts.length > 0 %}');
    assert.strictEqual(result.template, '{% if posts.length > 0 %}');
  });
});

describe('compileLiquid case statements', () => {
  test('compiles case statement', async () => {
    const result = await compileLiquid('{% case post.status %}');
    assert.strictEqual(result.template, '{% case post.status %}');
  });

  test('compiles when clause', async () => {
    const result = await compileLiquid('{% when "published" %}');
    assert.strictEqual(result.template, '{% when "published" %}');
  });

  test('compiles when with multiple values', async () => {
    const result = await compileLiquid('{% when "draft", "pending" %}');
    assert.strictEqual(result.template, '{% when "draft", "pending" %}');
  });
});

describe('compileLiquid assignments', () => {
  test('compiles assign statement', async () => {
    const result = await compileLiquid('{% assign title = post.title %}');
    assert.strictEqual(result.template, '{% assign title = post.title %}');
  });

  test('compiles assign with expression', async () => {
    const result = await compileLiquid('{% assign count = posts.length %}');
    assert.strictEqual(result.template, '{% assign count = posts.length %}');
  });
});

describe('compileLiquid full template', () => {
  test('compiles complete template', async () => {
    const template = `
{% for post in posts %}
  <article>
    <h2>{{ post.title }}</h2>
    <time>{{ post.published_at }}</time>
    {% if post.featured %}
      <span class="featured">Featured</span>
    {% endif %}
    <p>{{ post.excerpt }}</p>
  </article>
{% endfor %}
`;

    const result = await compileLiquid(template);

    assert.ok(result.template.includes('{{ post.title }}'));
    assert.ok(result.template.includes('{{ post.publishedAt }}'));
    assert.ok(result.template.includes('{% if post.featured %}'));
    assert.ok(result.template.includes('{% for post in posts %}'));
    assert.strictEqual(result.errors.length, 0);
  });

  test('handles template with no Ruby expressions', async () => {
    const template = '<h1>Hello World</h1>';
    const result = await compileLiquid(template);
    assert.strictEqual(result.template, '<h1>Hello World</h1>');
  });

  test('preserves non-Ruby Liquid tags', async () => {
    const template = '{% include "header" %}{% raw %}{{ not parsed }}{% endraw %}';
    const result = await compileLiquid(template);
    assert.ok(result.template.includes('{% include "header" %}'));
    assert.ok(result.template.includes('{% raw %}'));
  });
});
