// Test the ErbFileTransformer

import { ErbFileTransformer } from './dist/erb_file_transformer.mjs';

const ARTICLE_FORM = `import ['useState', 'useEffect'], from: 'react'
import ['setupDatabase'], from: '../lib/db.js'
import Article, from: '../models/article.js'

def ArticleForm(articleId: nil)
  title, setTitle = useState('')
  body, setBody = useState('')
  loading, setLoading = useState(!!articleId)
  saving, setSaving = useState(false)

  useEffect -> {
    return unless articleId

    setupDatabase().then do
      Article.find(articleId).then do |article|
        if article
          setTitle(article.title)
          setBody(article.body)
        end
        setLoading(false)
      end
    end
  }, [articleId]

  handleSubmit = ->(e) {
    e.preventDefault()
    setSaving(true)
    setupDatabase().then do
      if articleId
        Article.find(articleId).then do |article|
          article.title = title
          article.body = body
          article.save().then do
            window.location.href = "/articles/" + articleId
          end
        end
      else
        Article.create(title: title, body: body).then do |article|
          window.location.href = "/articles/" + article.id
        end
      end
    end
  }

  render
end

export default ArticleForm
__END__
<div>
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
</div>`;

console.log('Testing ErbFileTransformer');
console.log('='.repeat(50));

try {
  const result = await ErbFileTransformer.transform(ARTICLE_FORM);

  if (result.errors.length > 0) {
    console.log('✗ Transform failed with errors:');
    for (const err of result.errors) {
      console.log(`  ${err.type}: ${err.message}`);
      if (err.stack) {
        console.log(`  Stack: ${err.stack.split('\n').slice(0, 5).join('\n  ')}`);
      }
    }
    process.exit(1);
  }

  console.log('✓ Transform succeeded');
  console.log(`  Output length: ${result.component.length} chars`);
  console.log();
  console.log('Output:');
  console.log('-'.repeat(50));
  console.log(result.component);
} catch (e) {
  console.log('✗ Transform threw error:');
  console.log(`  ${e.message}`);
  console.log(`  ${e.stack?.split('\n').slice(1, 4).join('\n')}`);
  process.exit(1);
}
