// Test the ErbToJsx JavaScript converter against actual blog templates

import { initPrism } from './ruby2js.js';
import { ErbToJsx } from './dist/erb_to_jsx.mjs';

await initPrism();

const BLOG_TEMPLATES = {
  article_list: `<div>
  <% if loading %>
    <p class="meta">Loading articles...</p>
  <% end %>
  <% if !loading && articles.length == 0 %>
    <p>No articles yet. <a href="/articles/new">Create one!</a></p>
  <% end %>
  <% if !loading && articles.length > 0 %>
    <% articles.each do |article| %>
      <div class="card">
        <h2 style={{marginTop: 0}}>
          <a href={"/articles/" + article.id}><%= article.title %></a>
        </h2>
        <p><%= article.body.slice(0, 150) %>{article.body.length > 150 ? '...' : ''}</p>
        <p class="meta">Created: {new Date(article.createdAt).toLocaleDateString()}</p>
        <div class="actions">
          <a href={"/articles/" + article.id} class="btn btn-secondary">View</a>
          <a href={"/articles/" + article.id + "/edit"} class="btn btn-secondary">Edit</a>
          <button class="btn btn-danger" onClick={-> { handleDelete(article) }}>Delete</button>
        </div>
      </div>
    <% end %>
  <% end %>
</div>`,

  article_form: `<div>
  <% if loading %>
    <p class="meta">Loading...</p>
  <% end %>
  <% unless loading %>
    <form onSubmit={handleSubmit}>
      <div class="form-group">
        <label htmlFor="title">Title</label>
        <input type="text" id="title" value={title} onChange={->(e) { setTitle(e.target.value) }} disabled={saving} />
      </div>
      <div class="form-group">
        <label htmlFor="body">Body</label>
        <textarea id="body" value={body} onChange={->(e) { setBody(e.target.value) }} disabled={saving} />
      </div>
      <div class="actions">
        <button type="submit" class="btn btn-primary" disabled={saving}>
          {saving ? 'Saving...' : (articleId ? 'Update Article' : 'Create Article')}
        </button>
        <a href={articleId ? "/articles/" + articleId : "/articles"} class="btn btn-secondary">Cancel</a>
      </div>
    </form>
  <% end %>
</div>`,

  comment_form: `<form onSubmit={handleSubmit}>
  <div class="form-group">
    <label htmlFor="commenter">Name</label>
    <input
      type="text"
      id="commenter"
      value={commenter}
      onChange={->(e) { setCommenter(e.target.value) }}
      disabled={saving}
    />
  </div>

  <div class="form-group">
    <label htmlFor="comment-body">Comment</label>
    <textarea
      id="comment-body"
      value={body}
      onChange={->(e) { setBody(e.target.value) }}
      rows={3}
      style={{minHeight: '80px'}}
      disabled={saving}
    />
  </div>

  <button type="submit" class="btn btn-primary" disabled={saving || commenter.trim() == '' || body.trim() == ''}>
    {saving ? 'Adding...' : 'Add Comment'}
  </button>
</form>`
};

console.log('Testing ErbToJsx against blog templates');
console.log('='.repeat(50));

let passed = 0;
let failed = 0;

for (const [name, template] of Object.entries(BLOG_TEMPLATES)) {
  try {
    const result = ErbToJsx.convert(template);

    // Basic validation
    const hasJsx = result.includes('<') && result.includes('>');
    const hasNoErb = !result.includes('<%');
    const balancedBraces = (result.match(/\{/g) || []).length === (result.match(/\}/g) || []).length;

    if (hasJsx && hasNoErb && balancedBraces) {
      console.log(`✓ ${name}`);
      console.log(`  Output length: ${result.length} chars`);
      passed++;
    } else {
      console.log(`✗ ${name}`);
      console.log(`  hasJsx: ${hasJsx}, hasNoErb: ${hasNoErb}, balancedBraces: ${balancedBraces}`);
      failed++;
    }
  } catch (e) {
    console.log(`✗ ${name} (ERROR)`);
    console.log(`  Error: ${e.message}`);
    console.log(`  Stack: ${e.stack?.split('\n').slice(0, 3).join('\n')}`);
    failed++;
  }
}

console.log('='.repeat(50));
console.log(`Results: ${passed} passed, ${failed} failed`);

// Show sample output
console.log('\nSample output (article_form):');
console.log('-'.repeat(50));
try {
  console.log(ErbToJsx.convert(BLOG_TEMPLATES.article_form));
} catch (e) {
  console.log(`Error: ${e.message}`);
}

process.exit(failed > 0 ? 1 : 0);
