---
order: 618
title: Path Helpers
top_section: Juntos
category: juntos
---

# Path Helpers

Path helpers in Juntos return callable objects with HTTP methods. This enables Server Functions-style data fetching where the same code works on both browser and server targets.

{% toc %}

## Overview

Traditional Rails path helpers return URL strings:

```ruby
articles_path        # => "/articles"
article_path(1)      # => "/articles/1"
```

Juntos path helpers return **callable objects** with HTTP methods:

```ruby
articles_path.get()                      # GET /articles.json
articles_path.get(page: 2)               # GET /articles.json?page=2
articles_path.post(article: { title: "New" })  # POST /articles.json
article_path(1).patch(article: { ... })  # PATCH /articles/1.json
article_path(1).delete                   # DELETE /articles/1.json
```

All methods return native `Response` objects (browser) or synthetic equivalents that implement the same interface.

## HTTP Methods

### get(params)

Makes a GET request. Parameters become query string:

```ruby
# Simple fetch
notes_path.get()
# => GET /notes.json

# With query parameters
notes_path.get(page: 2, per_page: 10)
# => GET /notes.json?page=2&per_page=10

# Search query
notes_path.get(q: "search term")
# => GET /notes.json?q=search+term
```

### post(params)

Makes a POST request. Parameters become JSON body:

```ruby
# Create new record
notes_path.post(note: { title: "Hello", body: "World" })
# => POST /notes.json
# => Content-Type: application/json
# => Body: {"note":{"title":"Hello","body":"World"}}
```

### patch(params) / put(params)

Makes a PATCH or PUT request. Parameters become JSON body:

```ruby
# Update existing record
note_path(1).patch(note: { title: "Updated" })
# => PATCH /notes/1.json
# => Body: {"note":{"title":"Updated"}}
```

### delete(params)

Makes a DELETE request:

```ruby
# Delete record
note_path(1).delete
# => DELETE /notes/1.json
```

## Response Objects

All HTTP methods return a `PathHelperPromise` that wraps the response. This provides convenience methods for common patterns:

### Shorthand Syntax (Recommended)

The `.json`, `.text`, `.blob`, and `.arrayBuffer` methods accept an optional block, providing a concise way to handle responses:

```ruby
# Parse JSON response
notes_path.get.json do |data|
  setNotes(data)
end

# Create and use result
notes_path.post(note: params).json do |note|
  setNotes([note, *notes])
end

# Get text response
article_path(1).get(format: 'html').text do |html|
  setContent(html)
end
```

### Full Response Access

When you need access to response status, headers, or conditional parsing, use `.then`:

```ruby
# Check status before parsing
notes_path.post(note: params).then do |response|
  if response.ok
    response.json.then { |note| handleSuccess(note) }
  else
    response.json.then { |errors| handleErrors(errors) }
  end
end
```

### Without Block

The convenience methods also work without a block, returning a promise that resolves directly to the parsed data:

```ruby
# These return Promise<data> instead of Promise<Response>
data = await notes_path.get.json
text = await article_path(1).get(format: 'html').text
```

### Response Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `json()` | Promise<any> | Parse body as JSON |
| `text()` | Promise<string> | Get body as text |
| `blob()` | Promise<Blob> | Get body as Blob |
| `arrayBuffer()` | Promise<ArrayBuffer> | Get body as ArrayBuffer |

### Response Properties

| Property | Type | Description |
|----------|------|-------------|
| `ok` | boolean | True if status is 200-299 |
| `status` | number | HTTP status code |
| `statusText` | string | HTTP status message |
| `headers` | Headers | Response headers |

## Format Parameter

Path helpers default to JSON format. Override with the `format` parameter:

```ruby
# JSON (default)
notes_path.get()
# => GET /notes.json

# Explicit JSON
notes_path.get(format: 'json')
# => GET /notes.json

# HTML
notes_path.get(format: 'html')
# => GET /notes.html

# Turbo Stream
note_path(1).patch(note: updates, format: 'turbo_stream')
# => PATCH /notes/1.turbo_stream
```

The format also sets the appropriate `Accept` header:

| Format | Accept Header |
|--------|---------------|
| `json` | `application/json` |
| `html` | `text/html` |
| `turbo_stream` | `text/vnd.turbo-stream.html` |

## CSRF Protection

Mutating requests (POST, PATCH, PUT, DELETE) automatically include CSRF tokens:

```javascript
// Token read from <meta name="csrf-token">
headers['X-Authenticity-Token'] = token
```

This works automatically—no configuration needed. Ensure your layout includes the CSRF meta tag:

```erb
<head>
  <%= csrf_meta_tags %>
</head>
```

## Target-Specific Behavior

Path helpers work differently based on the build target:

### Browser Target (Dexie, sql.js, etc.)

Path helpers invoke controllers **directly**:

1. `notes_path.get()` is called
2. Router matches path to `NotesController.index`
3. Controller executes against local database (IndexedDB)
4. Returns synthetic Response wrapping the result

```
notes_path.get() → Router.match() → Controller.index() → Synthetic Response
```

### Server Target (Node.js, Cloudflare, etc.)

Path helpers make HTTP **fetch** requests:

1. `notes_path.get()` is called
2. Fetch request sent to `/notes.json`
3. Server routes to controller, queries database
4. Returns native Response object

```
notes_path.get() → fetch('/notes.json') → HTTP Response
```

### Same Code, Different Runtime

This abstraction enables truly portable code:

```ruby
# This exact code works on both targets
notes_path.get(q: searchQuery).json do |data|
  setNotes(data)
end
```

## Backward Compatibility

Path helpers still work as strings when coerced:

```ruby
# String coercion (backward compatible)
%x{ <a href={articles_path}>All Articles</a> }
navigate(article_path(article))

# Template literal
url = "#{articles_path}/archive"
```

The helpers implement `toString()` and `valueOf()` for seamless string conversion.

## Controller Setup

For path helpers to return JSON, controllers must respond to JSON format:

<div data-controller="combo" data-selfhost="true" data-options='{
  "eslevel": 2022,
  "filters": ["controller", "esm", "functions"]
}'></div>

```ruby
class NotesController < ApplicationController
  def index
    @notes = Note.all

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
end
```

## Usage Patterns

### Loading Data on Mount

```ruby
export default def NotesList()
  notes, setNotes = useState([])
  loading, setLoading = useState(true)

  useEffect(-> {
    notes_path.get.json do |data|
      setNotes(data)
      setLoading(false)
    end
  }, [])

  # render...
end
```

### Create with Optimistic Update

```ruby
handleCreate = ->(params) {
  # Optimistic: add placeholder
  tempNote = { id: "temp", ...params }
  setNotes([tempNote, *notes])

  notes_path.post(note: params).json do |note|
    # Replace placeholder with real record
    setNotes(notes.map { |n| n.id == "temp" ? note : n })
  end
}
```

### Update with Error Handling

When you need to check response status, use `.then` for full response access:

```ruby
handleUpdate = ->(id, updates) {
  note_path(id).patch(note: updates).then do |response|
    if response.ok
      response.json.then do |updated|
        setNotes(notes.map { |n| n.id == id ? updated : n })
      end
    else
      response.json.then { |errors| setErrors(errors) }
    end
  end
}
```

For simpler cases where you just need the data:

```ruby
handleUpdate = ->(id, updates) {
  note_path(id).patch(note: updates).json do |updated|
    setNotes(notes.map { |n| n.id == id ? updated : n })
  end
}
```

### Delete with Confirmation

```ruby
handleDelete = ->(id) {
  return unless confirm("Are you sure?")

  note_path(id).delete.then do |response|
    if response.ok
      setNotes(notes.filter { |n| n.id != id })
    end
  end
}
```

### Pagination

```ruby
loadPage = ->(page) {
  notes_path.get(page: page, per_page: 20).json do |data|
    setNotes(data)
  end
}
```

### Search with Debounce

```ruby
searchTimeout, setSearchTimeout = useState(nil)

handleSearch = ->(query) {
  clearTimeout(searchTimeout) if searchTimeout

  timeout = setTimeout(-> {
    notes_path.get(q: query).json do |data|
      setNotes(data)
    end
  }, 300)

  setSearchTimeout(timeout)
}
```

## Turbo Stream Responses

For Turbo Stream responses, use the `turbo_stream` format:

```ruby
handleUpdate = ->(id, updates) {
  note_path(id).patch(note: updates, format: 'turbo_stream').text do |html|
    Turbo.renderStreamMessage(html)
  end
}
```

The controller responds with Turbo Stream actions:

```ruby
respond_to do |format|
  format.turbo_stream {
    render turbo_stream: turbo_stream.replace(dom_id(@note), @note)
  }
end
```

## Generated Code

Path helpers are generated from `config/routes.rb`:

```ruby
# config/routes.rb
Rails.application.routes.draw do
  resources :notes
end
```

Generates `config/paths.js`:

```javascript
import { createPathHelper } from 'ruby2js-rails/path_helper.mjs';

function extract_id(obj) {
  return obj?.id ?? obj;
}

export function notes_path() {
  return createPathHelper('/notes');
}

export function note_path(note) {
  return createPathHelper(`/notes/${extract_id(note)}`);
}

export function new_note_path() {
  return createPathHelper('/notes/new');
}

export function edit_note_path(note) {
  return createPathHelper(`/notes/${extract_id(note)}/edit`);
}
```

## Next Steps

- Try the [Notes Demo](/docs/juntos/demos/notes) for a complete example
- Read about [Architecture](/docs/juntos/architecture) to understand the build process
- See [Hotwire](/docs/juntos/hotwire) for Turbo Stream integration
