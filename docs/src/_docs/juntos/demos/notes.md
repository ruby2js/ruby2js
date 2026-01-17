---
order: 659
title: Notes Demo
top_section: Juntos
category: juntos/demos
hide_in_toc: true
---

A notes app demonstrating Server Functions-style path helpers. Path helpers return objects with HTTP methods (get, post, patch, delete) that return Response objects. The same code runs on Rails, in browsers with IndexedDB, and on Node.js with SQLite.

{% toc %}

## Create the App

```bash
curl -sL https://raw.githubusercontent.com/ruby2js/ruby2js/master/test/notes/create-notes | bash -s notes
cd notes
```

This creates a Rails app with:

- **Note model** — title, body, timestamps
- **Validations** — `validates :title, presence: true`, `validates :body, presence: true`
- **Scopes** — `scope :search`, `scope :recent`
- **React view** — RBX components with path helper RPC calls
- **JSON API** — Controller responds to both HTML and JSON formats
- **Tailwind CSS** — styled sidebar and editor layout

## Run with Rails

First, verify it works as a standard Rails app:

```bash
RAILS_ENV=production bin/rails db:prepare
bin/rails server -e production
```

Open http://localhost:3000. Create notes. Search them. Edit them. This is Rails as you know it.

## Run in the Browser

Stop Rails. Run the same app in your browser:

```bash
bin/juntos dev -d dexie
```

Open http://localhost:3000. Same notes app. Same functionality. But now:

- **No Ruby runtime** — the browser runs transpiled JavaScript
- **IndexedDB storage** — data persists in your browser via [Dexie](https://dexie.org/)
- **Path helper RPC** — `notes_path.get()` invokes the controller directly
- **Synthetic Response** — returns Response-like objects for seamless API

## Run on Node.js

```bash
bin/juntos db:prepare -d sqlite
bin/juntos up -d sqlite
```

Open http://localhost:3000. Same notes app—but now Node.js serves requests, and path helper calls become HTTP fetch requests to the server.

## Path Helper RPC

The key innovation in this demo is **path helpers with HTTP methods**. Instead of returning URL strings, path helpers return callable objects:

```ruby
# Traditional path helpers return strings
articles_path        # => "/articles"
article_path(1)      # => "/articles/1"

# Path helper RPC returns objects with HTTP methods
notes_path.get()                    # GET /notes.json
notes_path.get(q: "search term")    # GET /notes.json?q=search+term
notes_path.post(note: { title: "New" })  # POST /notes.json
note_path(1).patch(note: { title: "Updated" })  # PATCH /notes/1.json
note_path(1).delete                 # DELETE /notes/1.json
```

### Response Objects

All methods return native `Response` objects (or synthetic equivalents in the browser):

```ruby
# Fetch notes and parse JSON
notes_path.get.json { |data| setNotes(data) }

# Create a note
notes_path.post(note: { title: "Hello", body: "World" }).json do |note|
  setNotes([note, *notes])
end
```

### JSON by Default

Path helper methods default to JSON format—the most common format for React component data fetching:

```ruby
notes_path.get()                  # GET /notes.json
notes_path.get(format: 'html')    # GET /notes.html (explicit)
```

### CSRF Protection

Mutating requests (POST, PATCH, PUT, DELETE) automatically include CSRF tokens from `<meta name="csrf-token">`:

```javascript
// Automatically added to headers
headers['X-Authenticity-Token'] = csrfToken
```

## The Code

### Controller with JSON Support

The controller uses `respond_to` to handle both HTML and JSON formats:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["controller", "esm", "functions"]
}'></div>

```ruby
class NotesController < ApplicationController
  before_action :set_note, only: [:show, :edit, :update, :destroy]

  def index
    @notes = Note.recent
    @notes = @notes.search(params[:q]) if params[:q].present?

    respond_to do |format|
      format.html
      format.json { render json: @notes }
    end
  end

  def create
    @note = Note.new(note_params)

    respond_to do |format|
      if @note.save
        format.html { redirect_to @note }
        format.json { render json: @note, status: :created }
      else
        format.html { render :new }
        format.json { render json: @note.errors, status: :unprocessable_entity }
      end
    end
  end

  private

  def set_note
    @note = Note.find(params[:id])
  end

  def note_params
    params.require(:note).permit(:title, :body)
  end
end
```

### RBX View with Path Helpers

The view uses path helpers to fetch and mutate data:

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["react", "esm", "functions"]
}'></div>

```ruby
# app/views/notes/Index.jsx.rb
import React, [useState, useEffect], from: 'react'
import [notes_path, note_path], from: '/config/paths.js'

export default def Index()
  notes, setNotes = useState([])
  searchQuery, setSearchQuery = useState("")

  # Load notes on mount and when search changes
  useEffect(-> {
    params = {}
    params[:q] = searchQuery if searchQuery.length > 0

    notes_path.get(params).json { |data| setNotes(data) }
  }, [searchQuery])

  handleCreate = -> {
    notes_path.post(note: { title: "Untitled", body: "" }).json do |note|
      setNotes([note, *notes])
    end
  }

  handleUpdate = ->(id, updates) {
    note_path(id).patch(note: updates).json do |updated|
      setNotes(notes.map { |n| n.id == updated.id ? updated : n })
    end
  }

  handleDelete = ->(id) {
    note_path(id).delete.then do
      setNotes(notes.filter { |n| n.id != id })
    end
  }

  # ... render JSX
end
```

## Target Behavior

The same path helper calls work differently based on the build target:

| Target | Path Helper Behavior |
|--------|---------------------|
| Browser (Dexie) | Direct controller invocation, synthetic Response |
| Server (Node.js, etc.) | HTTP fetch to server endpoint |

### Browser Target

In the browser, `notes_path.get()` invokes the controller action directly:

1. Router matches the path to `NotesController.index`
2. Controller executes against local Dexie database
3. Returns synthetic Response with `.json()`, `.text()` methods

### Server Target

On Node.js (or Cloudflare, Vercel, etc.), `notes_path.get()` makes an HTTP request:

1. Fetch request to `/notes.json`
2. Server routes to controller, queries SQLite
3. Returns native Response object

## What This Demo Shows

### Server Functions-Style Data Fetching

This pattern is inspired by React Server Functions—data fetching happens through a unified API that works on both client and server:

```ruby
# Same code works everywhere
notes_path.get.json { |data| ... }
```

### Format Negotiation

Controllers respond to different formats based on Accept headers:

```ruby
respond_to do |format|
  format.html { render :index }
  format.json { render json: @notes }
end
```

Path helpers set the appropriate Accept header automatically.

### Scoped Queries via URL

Search queries become URL parameters:

```ruby
# Ruby code
notes_path.get(q: searchQuery)

# Results in
# GET /notes.json?q=searchQuery
```

## Comparison to Blog Demo

| Feature | Blog Demo | Notes Demo |
|---------|-----------|------------|
| Data fetching | Form submissions | Path helper RPC |
| Response format | HTML | JSON |
| View rendering | ERB templates | React components (RBX) |
| Reactivity | Turbo Streams | useState/useEffect |
| Pattern | Traditional Rails | Server Functions-style |

The Blog demo shows traditional Rails patterns. The Notes demo shows a modern React-style approach where the view layer manages state and fetches data via API calls.

## Next Steps

- Read the [Path Helpers](/docs/juntos/path-helpers) guide for complete API documentation
- Try the [Workflow Builder](/docs/juntos/demos/workflow-builder) for React Flow integration
- Check [Architecture](/docs/juntos/architecture) for how path helpers are generated
