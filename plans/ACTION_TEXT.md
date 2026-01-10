# Action Text for Juntos

## Overview

Bring Rails' Action Text pattern to Juntos: a `has_rich_text` model macro with Tiptap as the editor. Works offline, runs on all targets, optional real-time collaboration.

## Prerequisites

None. This is independent of UNIFIED_VIEWS.md and REACT_ECOSYSTEM_DEMO.md.

Tiptap works with Stimulus—no RBX or React required.

## Motivation

### Rails Action Text

Rails provides Action Text for rich text editing:

```ruby
class Article < ApplicationRecord
  has_rich_text :body
end
```

```erb
<%= form.rich_text_area :body %>
```

Under the hood:
- `has_rich_text` creates a polymorphic association to `ActionText::RichText`
- Trix editor handles the UI
- Active Storage handles embedded attachments
- Content stored as HTML

### Juntos Needs This

Rich text is table stakes for many applications. Currently Juntos has no equivalent—you'd wire up an editor manually.

### Why Tiptap over Trix/Lexxy

| Editor | Collaboration | Juntos Targets | Ecosystem |
|--------|---------------|----------------|-----------|
| Trix | No | Awkward (Rails-specific) | Basecamp only |
| Lexxy | No | Awkward (Rails-specific) | Basecamp only |
| Tiptap | Yes (Yjs) | All targets | Large plugin ecosystem |

Trix and Lexxy are designed for Rails' Action Text. Tiptap is framework-agnostic and works everywhere Juntos runs.

## Design

### Model Layer

```ruby
class Article < ApplicationRecord
  has_rich_text :body
end
```

Generates:
- `body` accessor that returns RichText instance
- `body=` setter that accepts HTML or Tiptap JSON
- Association to RichText model

### RichText Model

```ruby
class RichText < ApplicationRecord
  belongs_to :record, polymorphic: true

  validates :content, presence: true
end
```

Schema:
```ruby
create_table :rich_texts do |t|
  t.string :name, null: false
  t.text :content
  t.references :record, polymorphic: true, null: false
  t.timestamps
end
```

### Storage Format

Two options:

| Format | Pros | Cons |
|--------|------|------|
| HTML | Portable, renders directly | Loses editor state |
| Tiptap JSON | Full fidelity, collaboration-ready | Requires rendering |

**Default: HTML** for simplicity. Option for JSON when collaboration is enabled.

### Editor Component

Stimulus controller wrapping Tiptap:

```ruby
# app/javascript/controllers/rich_text_controller.rb
class RichTextController < Stimulus::Controller
  def connect
    @editor = Editor.new(
      element: element,
      extensions: [StarterKit],
      content: contentValue,
      onUpdate: -> { inputTarget.value = @editor.getHTML() }
    )
  end

  def disconnect
    @editor.destroy()
  end
end
```

### View Helper

```erb
<%= form.rich_text_area :body %>
```

Generates:

```html
<div data-controller="rich-text"
     data-rich-text-content-value="<p>Existing content...</p>">
  <input type="hidden" name="article[body]" data-rich-text-target="input">
  <div data-rich-text-target="editor"></div>
</div>
```

### Collaboration (Optional)

When enabled, adds Yjs extensions:

```ruby
# config/ruby2js.yml
action_text:
  collaboration: true
  provider: webrtc  # or: websocket, liveblocks
```

```ruby
# app/javascript/controllers/rich_text_controller.rb
class RichTextController < Stimulus::Controller
  def connect
    if collaborationEnabled
      @ydoc = Y.Doc.new
      @provider = WebrtcProvider.new(documentId, @ydoc)

      @editor = Editor.new(
        element: element,
        extensions: [
          StarterKit,
          Collaboration.configure(document: @ydoc),
          CollaborationCursor.configure(provider: @provider, user: currentUser)
        ]
      )
    else
      # Non-collaborative setup
    end
  end
end
```

### Cross-Target Support

| Target | Storage | Collaboration Provider |
|--------|---------|----------------------|
| Browser | IndexedDB | y-webrtc (P2P) |
| Node.js | SQLite/Postgres | y-websocket |
| Edge | D1/Neon | y-websocket or y-webrtc |
| Capacitor | SQLite | y-webrtc |
| Electron | SQLite | y-webrtc or y-websocket |

Offline editing works on all targets—RichText model saves to local database. Collaboration requires connectivity but degrades gracefully.

## Implementation

### Phase 1: Model Macro

```ruby
# lib/ruby2js/filter/rails/model.rb
def on_send(node)
  # ... existing has_many, belongs_to, etc.

  if method == :has_rich_text
    name = args.first.children.first
    # Generate association and accessors
  end
end
```

Transpiles to:

```javascript
class Article extends ApplicationRecord {
  static richTextAttributes = ['body'];

  get body() {
    return this._richTexts?.body;
  }

  set body(content) {
    this._richTexts ||= {};
    this._richTexts.body = content;
  }
}
```

### Phase 2: RichText Model

Add to Juntos runtime:

```ruby
# lib/juntos/models/rich_text.rb
class RichText < ApplicationRecord
  belongs_to :record, polymorphic: true

  validates :name, presence: true
  validates :content, presence: true
end
```

Migration generator:

```bash
bin/juntos generate rich_text
# Creates migration for rich_texts table
```

### Phase 3: Stimulus Controller

```ruby
# lib/juntos/templates/rich_text_controller.rb
class RichTextController < Stimulus::Controller
  # ... full implementation
end
```

Automatically included when `has_rich_text` is used.

### Phase 4: View Helper

Add to helpers filter:

```ruby
# lib/ruby2js/filter/rails/helpers.rb
def process_rich_text_area(form, attribute)
  # Generate Tiptap-compatible markup
end
```

### Phase 5: Collaboration

Optional Yjs integration:

```ruby
# When collaboration: true in config
# Extend Stimulus controller with Yjs setup
```

## Demo: Blog with Rich Text

Extend the existing blog demo:

```bash
curl -sL .../create-blog-rich-text | bash
```

Changes from base blog:
- Article model: `has_rich_text :body` instead of `body:text`
- Form: `<%= form.rich_text_area :body %>` instead of `text_area`
- Show view: `<%= @article.body %>` renders HTML

~50 lines delta from create-blog.

### With Collaboration

```bash
curl -sL .../create-blog-collaborative | bash
```

Additional:
- Yjs setup in Stimulus controller
- WebRTC provider for P2P sync
- Cursor colors and user names

~100 lines delta from create-blog.

## File Structure

```
lib/
  ruby2js/
    filter/
      rails/
        model.rb          # Add has_rich_text macro
        helpers.rb        # Add rich_text_area helper

  juntos/
    models/
      rich_text.rb        # RichText model

    templates/
      rich_text_controller.rb  # Stimulus controller

    generators/
      rich_text_generator.rb   # Migration generator
```

## Configuration

```yaml
# config/ruby2js.yml
action_text:
  # Storage format
  format: html          # or: json (for collaboration)

  # Editor configuration
  editor:
    toolbar: full       # or: minimal, custom
    placeholder: "Write something..."

  # Collaboration (optional)
  collaboration: false  # or: true
  provider: webrtc      # or: websocket, liveblocks

  # Attachments (future)
  # attachments: true
  # storage: active_storage
```

## Comparison with Rails

| Feature | Rails Action Text | Juntos Action Text |
|---------|-------------------|-------------------|
| Model macro | `has_rich_text` | `has_rich_text` |
| Editor | Trix (Lexxy soon) | Tiptap |
| Storage | Active Storage | Pluggable |
| Collaboration | No | Yes (Yjs) |
| Offline | No | Yes |
| Targets | Server only | All Juntos targets |

## Future Extensions

### Attachments

```ruby
class Article < ApplicationRecord
  has_rich_text :body, attachments: true
end
```

Would integrate with a future Active Storage abstraction.

### Custom Extensions

```yaml
action_text:
  extensions:
    - mention        # @user mentions
    - hashtag        # #tag support
    - code_block     # Syntax highlighting
    - table          # Table editing
```

Tiptap's extension ecosystem is large—expose configuration for common ones.

### Multiple Editors

```ruby
class Article < ApplicationRecord
  has_rich_text :body
  has_rich_text :summary, toolbar: :minimal
end
```

Different configurations per attribute.

## Success Criteria

1. `has_rich_text :body` works like Rails
2. Tiptap editor renders with Stimulus (no React)
3. Content persists to RichText model
4. Works offline on all targets
5. Optional collaboration with Yjs
6. ~50 lines to add rich text to existing demo
7. ~100 lines for collaborative version

## Timeline Estimate

| Phase | Effort |
|-------|--------|
| 1. Model macro | 1-2 days |
| 2. RichText model + migration | 1 day |
| 3. Stimulus controller | 2-3 days |
| 4. View helper | 1 day |
| 5. Collaboration | 2-3 days |
| **Total** | **~1.5-2 weeks** |

Phases 1-4 deliver non-collaborative rich text editing. Phase 5 adds collaboration as an enhancement.
