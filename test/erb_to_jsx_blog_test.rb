#!/usr/bin/env ruby
# Test the ErbToJsx converter against actual blog templates

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'ruby2js'
require 'ruby2js/erb_to_jsx'

# Actual templates from the Astro blog demo
BLOG_TEMPLATES = {
  article_list: <<~ERB,
    <div>
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
    </div>
  ERB

  article_show: <<~ERB,
    <div>
      <% if loading %>
        <p class="meta">Loading article...</p>
      <% end %>
      <% if !loading && !article %>
        <p>Article not found. <a href="/articles">Back to articles</a></p>
      <% end %>
      <% if !loading && article %>
        <h1><%= article.title %></h1>
        <p class="meta">Created: {new Date(article.createdAt).toLocaleDateString()}</p>
        <div class="card" style={{whiteSpace: 'pre-wrap'}}>
          <%= article.body %>
        </div>

        <div class="actions">
          <a href={"/articles/" + article.id + "/edit"} class="btn btn-secondary">Edit</a>
          <button class="btn btn-danger" onClick={handleDelete}>Delete</button>
          <a href="/articles" class="btn btn-secondary">Back to Articles</a>
        </div>

        <hr style={{margin: '2rem 0'}} />

        <h2>Comments</h2>
        <CommentList articleId={article.id} />

        <h3 style={{marginTop: '1.5rem'}}>Add a Comment</h3>
        <CommentForm articleId={article.id} />
      <% end %>
    </div>
  ERB

  article_form: <<~ERB,
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
    </div>
  ERB

  comment_list: <<~ERB,
    <div>
      <% if loading %>
        <p class="meta">Loading comments...</p>
      <% end %>
      <% if !loading && comments.length == 0 %>
        <p class="meta">No comments yet.</p>
      <% end %>
      <% if !loading && comments.length > 0 %>
        <% comments.each do |comment| %>
          <div class="card">
            <p><strong><%= comment.commenter %></strong></p>
            <p><%= comment.body %></p>
            <p class="meta">{new Date(comment.createdAt).toLocaleDateString()}</p>
            <button class="btn btn-danger" onClick={-> { handleDelete(comment) }} style={{marginTop: '0.5rem', padding: '0.25rem 0.5rem', fontSize: '0.875rem'}}>
              Delete
            </button>
          </div>
        <% end %>
      <% end %>
    </div>
  ERB

  comment_form: <<~ERB
    <form onSubmit={handleSubmit}>
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
    </form>
  ERB
}

# Run tests
puts "Testing ErbToJsx against blog templates"
puts "=" * 50

passed = 0
failed = 0

BLOG_TEMPLATES.each do |name, template|
  begin
    result = Ruby2JS::ErbToJsx.convert(template)

    # Basic validation: should produce valid-looking JSX
    has_jsx = result.include?('<') && result.include?('>')
    has_no_erb = !result.include?('<%')
    balanced_braces = result.count('{') == result.count('}')

    if has_jsx && has_no_erb && balanced_braces
      puts "✓ #{name}"
      puts "  Output length: #{result.length} chars"
      passed += 1
    else
      puts "✗ #{name}"
      puts "  has_jsx: #{has_jsx}, has_no_erb: #{has_no_erb}, balanced_braces: #{balanced_braces}"
      puts "  Output preview: #{result[0..200]}..."
      failed += 1
    end
  rescue => e
    puts "✗ #{name} (ERROR)"
    puts "  Error: #{e.message}"
    puts "  #{e.backtrace.first(3).join("\n  ")}"
    failed += 1
  end
end

puts "=" * 50
puts "Results: #{passed} passed, #{failed} failed"

# Show one complete output for inspection
puts
puts "Sample output (article_form):"
puts "-" * 50
puts Ruby2JS::ErbToJsx.convert(BLOG_TEMPLATES[:article_form])

exit(failed > 0 ? 1 : 0)
