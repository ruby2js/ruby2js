# Blog Demo Real-Time Updates Plan

This plan covers adding real-time updates to the `demo/blog` Rails 8.1 application using Turbo Streams with ActionCable.

## Goal

- Index page updates automatically when new articles or comments are added
- Article show page updates automatically when new comments are added
- Uses built-in Rails 8.1 Turbo Streams broadcasting (no custom JavaScript needed)

## Current State

The demo/blog application has:
- **Turbo Rails** installed and configured
- **ActionCable** configured via `solid_cable` (but not actively used)
- **Standard CRUD** with HTTP redirects (no real-time)
- **Models**: Article (has_many :comments), Comment (belongs_to :article)

## Implementation

### Step 1: Add Broadcasting to Article Model

**File**: `demo/blog/app/models/article.rb`

```ruby
class Article < ApplicationRecord
  has_many :comments, dependent: :destroy

  broadcasts_to -> { "articles" }, inserts_by: :prepend

  validates :title, presence: true
  validates :body, presence: true, length: { minimum: 10 }
end
```

The `broadcasts_to` callback will:
- Broadcast to the "articles" stream when articles are created/updated/destroyed
- Prepend new articles to the list (newest first)

---

### Step 2: Add Broadcasting to Comment Model

**File**: `demo/blog/app/models/comment.rb`

```ruby
class Comment < ApplicationRecord
  belongs_to :article, touch: true

  broadcasts_to -> { "article_#{article_id}_comments" }, target: "comments"
end
```

The `broadcasts_to` callback will:
- Broadcast to the article-specific comments stream (e.g., "article_1_comments")
- The `touch: true` ensures the article's updated_at changes, triggering article broadcasts

---

### Step 3: Update Index View for Real-Time Article Updates

**File**: `demo/blog/app/views/articles/index.html.erb`

Add subscription at the top:
```erb
<%= turbo_stream_from "articles" %>
```

Wrap the articles list in a container with an ID:
```erb
<div id="articles">
  <%= render @articles %>
</div>
```

---

### Step 4: Update Article Partial with Turbo Frame

**File**: `demo/blog/app/views/articles/_article.html.erb`

Wrap the entire partial in a turbo frame:
```erb
<%= turbo_frame_tag dom_id(article) do %>
  <!-- existing article content -->
<% end %>
```

Add an identifiable element for the comment count so it can be updated:
```erb
<span id="<%= dom_id(article, :comments_count) %>">
  <%= pluralize(article.comments.count, "comment") %>
</span>
```

---

### Step 5: Update Show View for Real-Time Comment Updates

**File**: `demo/blog/app/views/articles/show.html.erb`

Add subscription at the top:
```erb
<%= turbo_stream_from "article_#{@article.id}_comments" %>
```

Wrap comments in a container:
```erb
<div id="comments">
  <%= render @article.comments %>
</div>
```

---

### Step 6: Update Comment Partial with Turbo Frame

**File**: `demo/blog/app/views/comments/_comment.html.erb`

Wrap the partial in a turbo frame:
```erb
<%= turbo_frame_tag dom_id(comment) do %>
  <!-- existing comment content -->
<% end %>
```

---

### Step 7: Update Comments Controller for Turbo Stream Responses

**File**: `demo/blog/app/controllers/comments_controller.rb`

Update the create action to respond with Turbo Stream format:
```ruby
def create
  @article = Article.find(params[:article_id])
  @comment = @article.comments.create(comment_params)

  respond_to do |format|
    format.turbo_stream
    format.html { redirect_to @article }
  end
end
```

---

### Step 8: Create Turbo Stream Template for Comment Creation

**File**: `demo/blog/app/views/comments/create.turbo_stream.erb`

```erb
<%= turbo_stream.append "comments", @comment %>
<%= turbo_stream.replace dom_id(@article, :comments_count) do %>
  <span id="<%= dom_id(@article, :comments_count) %>">
    <%= pluralize(@article.comments.count, "comment") %>
  </span>
<% end %>
```

This template:
- Appends the new comment to the comments container
- Updates the comment count display

---

## Files to Modify

| File | Change |
|------|--------|
| `app/models/article.rb` | Add `broadcasts_to` |
| `app/models/comment.rb` | Add `broadcasts_to`, `touch: true` |
| `app/views/articles/index.html.erb` | Add `turbo_stream_from`, wrap articles |
| `app/views/articles/_article.html.erb` | Wrap in `turbo_frame_tag`, add comments count ID |
| `app/views/articles/show.html.erb` | Add `turbo_stream_from`, wrap comments |
| `app/views/comments/_comment.html.erb` | Wrap in `turbo_frame_tag` |
| `app/controllers/comments_controller.rb` | Add `respond_to` with turbo_stream |

## File to Create

| File | Purpose |
|------|---------|
| `app/views/comments/create.turbo_stream.erb` | Turbo Stream response for comment creation |

---

## How It Works

### Broadcasting Flow

```
User creates comment
       ↓
Comment model after_commit callback fires
       ↓
broadcasts_to sends Turbo Stream to ActionCable
       ↓
All subscribed browsers receive WebSocket message
       ↓
Turbo automatically applies DOM updates
```

### Subscription Flow

```
User visits /articles (index)
       ↓
turbo_stream_from "articles" renders
       ↓
Browser establishes WebSocket to ActionCable
       ↓
Browser subscribes to "articles" stream
       ↓
Any article changes broadcast to all viewers
```

---

## Testing

1. Open two browser windows to `/articles`
2. Create a new article in one window
3. Verify it appears in both windows without refresh

4. Open two browser windows to `/articles/1`
5. Add a comment in one window
6. Verify comment appears in both windows
7. Verify comment count updates on index page

---

## Dependencies

Already present in the application:
- `turbo-rails` gem (Hotwire Turbo)
- `solid_cable` gem (ActionCable adapter)
- ActionCable configured in `config/cable.yml`

No additional gems or configuration needed.

---

## Notes

- The `broadcasts_to` macro automatically generates `after_create_commit`, `after_update_commit`, and `after_destroy_commit` callbacks
- No custom JavaScript is required; Turbo handles WebSocket connections and DOM updates
- The `dom_id` helper generates unique IDs like `article_1`, `comment_5`, etc.
- The `touch: true` option on `belongs_to` ensures parent article broadcasts when comments change
- Use `inserts_by: :prepend` to show newest items first, or `:append` (default) for oldest first
