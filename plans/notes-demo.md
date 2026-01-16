# Plan: React Notes Demo for Ruby2JS

## Goal

Create a Notes demo app that demonstrates RSC-style path helpers while running unchanged on both browser (Dexie/IndexedDB) and server (SQLite/Postgres) targets. Modeled after the [React Server Components demo](https://github.com/reactjs/server-components-demo).

## Features

- Create, edit, delete notes
- Search notes by title
- Sidebar with note list
- Real-time updates via Turbo Streams
- Loading states with Suspense-style patterns

## Same Source, Two Targets

| Target | Data Storage | Path Helper Behavior |
|--------|--------------|---------------------|
| Browser | Dexie/IndexedDB | Direct controller invocation, synthetic Response |
| Server (Node, etc.) | SQLite/Postgres | HTTP fetch to server |

## Architecture

```
┌─────────────────────────────────────────┐
│              RBX Views                  │
│  (React components in Ruby syntax)      │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│           Path Helpers                  │
│  notes_path.get(q: "...", format: :json)│
│  note_path(id).patch(note: {...})       │
└─────────────────────────────────────────┘
                    │
        ┌───────────┴───────────┐
        ▼                       ▼
┌───────────────┐       ┌───────────────┐
│    Browser    │       │    Server     │
│  Controller   │       │  Controller   │
│   (direct)    │       │   (HTTP)      │
└───────────────┘       └───────────────┘
        │                       │
        ▼                       ▼
┌───────────────┐       ┌───────────────┐
│     Dexie     │       │    SQLite/    │
│   IndexedDB   │       │   Postgres    │
└───────────────┘       └───────────────┘
```

## File Structure

```
demo/notes/
├── app/
│   ├── controllers/
│   │   └── notes_controller.rb
│   ├── models/
│   │   └── note.rb
│   ├── views/
│   │   └── notes/
│   │       ├── Index.rbx        # Main view with sidebar + editor
│   │       ├── _note_list.rbx   # Sidebar note list (partial)
│   │       └── _editor.rbx      # Note editor (partial)
│   └── components/
│       ├── SearchField.rbx
│       └── NotePreview.rbx
├── config/
│   └── routes.rb
├── db/
│   └── migrate/
│       └── 001_create_notes.rb
└── test/
    └── create-notes           # Setup script
```

## Model

```ruby
# app/models/note.rb
class Note < ApplicationRecord
  validates :title, presence: true
  validates :body, presence: true

  scope :search, ->(query) {
    where("title LIKE ?", "%#{query}%") if query.present?
  }

  scope :recent, -> { order(updated_at: :desc) }
end
```

**Migration:**
```ruby
create_table :notes do |t|
  t.string :title, null: false
  t.text :body, null: false
  t.timestamps
end

add_index :notes, :updated_at
add_index :notes, :title
```

## Controller

```ruby
# app/controllers/notes_controller.rb
class NotesController < ApplicationController
  def index
    notes = Note.recent
    notes = notes.search(params[:q]) if params[:q].present?

    respond_to do |format|
      format.html { render :index, notes: notes }
      format.json { render json: notes }
    end
  end

  def show
    note = Note.find(params[:id])

    respond_to do |format|
      format.html { render :show, note: note }
      format.json { render json: note }
    end
  end

  def create
    note = Note.create!(note_params)

    respond_to do |format|
      format.json { render json: note, status: :created }
      format.turbo_stream {
        render turbo_stream: turbo_stream.prepend("notes", partial: "note_preview", locals: { note: note })
      }
    end
  end

  def update
    note = Note.find(params[:id])
    note.update!(note_params)

    respond_to do |format|
      format.json { render json: note }
      format.turbo_stream {
        render turbo_stream: turbo_stream.replace(dom_id(note), partial: "note_preview", locals: { note: note })
      }
    end
  end

  def destroy
    note = Note.find(params[:id])
    note.destroy!

    respond_to do |format|
      format.json { head :no_content }
      format.turbo_stream {
        render turbo_stream: turbo_stream.remove(dom_id(note))
      }
    end
  end

  private

  def note_params
    params.require(:note).permit(:title, :body)
  end
end
```

## Routes

```ruby
# config/routes.rb
Rails.application.routes.draw do
  root "notes#index"
  resources :notes
end
```

## Main View (RBX)

```ruby
# app/views/notes/Index.rbx
import { notes_path, note_path } from '../../../config/paths.js'
import SearchField from 'components/SearchField'
import NotePreview from 'components/NotePreview'

export default def Index()
  notes, setNotes = useState([])
  selectedId, setSelectedId = useState(null)
  searchQuery, setSearchQuery = useState("")

  # Load notes on mount and when search changes
  useEffect(-> {
    notes_path.get(q: searchQuery, format: :json).then do |response|
      response.json.then { |data| setNotes(data) }
    end
  }, [searchQuery])

  selectedNote = notes.find { |n| n.id == selectedId }

  handleCreate = -> {
    notes_path.post(note: { title: "Untitled", body: "" }, format: :json).then do |response|
      response.json.then do |note|
        setNotes([note, ...notes])
        setSelectedId(note.id)
      end
    end
  }

  handleUpdate = ->(updates) {
    note_path(selectedId).patch(note: updates, format: :json).then do |response|
      response.json.then do |updated|
        setNotes(notes.map { |n| n.id == updated.id ? updated : n })
      end
    end
  }

  handleDelete = -> {
    note_path(selectedId).delete.then do
      setNotes(notes.filter { |n| n.id != selectedId })
      setSelectedId(null)
    end
  }

  %x{
    <div className="flex h-screen">
      {/* Sidebar */}
      <div className="w-80 border-r flex flex-col">
        <div className="p-4 border-b">
          <SearchField value={searchQuery} onChange={setSearchQuery} />
          <button onClick={handleCreate} className="mt-2 w-full btn">
            New Note
          </button>
        </div>
        <div className="flex-1 overflow-y-auto">
          {notes.map(note => (
            <NotePreview
              key={note.id}
              note={note}
              selected={note.id === selectedId}
              onClick={() => setSelectedId(note.id)}
            />
          ))}
        </div>
      </div>

      {/* Editor */}
      <div className="flex-1 p-4">
        {selectedNote ? (
          <Editor
            note={selectedNote}
            onUpdate={handleUpdate}
            onDelete={handleDelete}
          />
        ) : (
          <div className="text-gray-500 text-center mt-20">
            Select a note or create a new one
          </div>
        )}
      </div>
    </div>
  }
end
```

## Path Helper Usage Summary

| Action | Path Helper Call |
|--------|-----------------|
| List all notes | `notes_path.get(format: :json)` |
| Search notes | `notes_path.get(q: "query", format: :json)` |
| Get single note | `note_path(id).get(format: :json)` |
| Create note | `notes_path.post(note: {...}, format: :json)` |
| Update note | `note_path(id).patch(note: {...}, format: :json)` |
| Delete note | `note_path(id).delete` |

## Implementation Phases

### Phase 1: Basic Demo Structure
- Create demo/notes directory structure
- Implement Note model and migration
- Implement NotesController with JSON responses
- Create routes.rb

### Phase 2: RBX Views
- Index.rbx with sidebar and editor layout
- SearchField.rbx component
- NotePreview.rbx component
- Editor.rbx component (inline in Index or separate)

### Phase 3: Path Helper Integration
- Wire up path helpers for all CRUD operations
- Test on browser target (Dexie)
- Test on server target (SQLite)

### Phase 4: Real-time Updates
- Add Turbo Stream responses to controller
- Add Action Cable subscription for multi-window sync
- Test broadcast updates

### Phase 5: Polish
- Loading states
- Error handling
- Optimistic updates
- Tailwind styling

## Testing

```bash
# Browser target
bin/juntos up -t browser -d dexie
open http://localhost:5173/

# Node target
bin/juntos up -t node -d sqlite
open http://localhost:3000/
```

Both should behave identically - create notes in one, see them in the other (within same target), search works, edit works, delete works.

## Success Criteria

1. Same source code runs on both browser and server targets
2. All CRUD operations work via path helpers
3. Search with query params works
4. Real-time updates across browser windows
5. Clean, simple code that demonstrates the pattern

## Comparison to React Team Demo

| Feature | React Demo | Juntos Notes |
|---------|-----------|--------------|
| Server rendering | Express + custom RSC | Juntos runtime |
| Database | PostgreSQL only | Dexie OR SQLite/Postgres |
| Same source both targets | No | Yes |
| Path helpers | No (custom API) | Yes (Rails-style) |
| Real-time | No | Yes (Turbo Streams) |
| Ruby syntax | No | Yes |
