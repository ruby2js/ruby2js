# React Ecosystem Demo: Workflow Builder

## Overview

A demonstration that Ruby2JS/Juntos provides access to the React ecosystem when Hotwire isn't enough. The demo is a visual workflow builder using React Flow—something that genuinely requires React and can't be easily replicated with Stimulus.

## Prerequisites

- **UNIFIED_VIEWS.md Phase 4**: RBX file support must be implemented
  - `.rbx` file detection in builder
  - RBX transpilation with React filter
  - Mixed view types (ERB + RBX) in same application

## Motivation

### The Problem

Hotwire handles 90% of interactivity needs. Basecamp's Fizzy proves you can build a Kanban board with 6% JavaScript. But some things genuinely need React:

- Complex node-based editors (workflows, mind maps, diagrams)
- Deep integration with React component libraries
- Features where the React ecosystem has mature solutions and Hotwire would mean building from scratch

### The Solution

RBX files provide an escape hatch to the React ecosystem without leaving Ruby. When you need React, you write `.rbx`. When you don't, you stay with ERB/Phlex. Mix freely.

### Why React Flow?

| Criteria | React Flow |
|----------|------------|
| Requires React | Yes (no Stimulus equivalent) |
| Visually impressive | Yes (drag, connect, zoom, pan) |
| Touch support | Yes (works on mobile) |
| Self-contained | Yes (no cloud service dependency) |
| Practical use case | Workflow builder, mind map, process diagram |

Alternatives considered:
- **Tiptap**: Works with Stimulus (doesn't require React)
- **Liveblocks**: Requires cloud service (external dependency)
- **Recharts**: Charts can be embedded without React (weak demo)

### Beyond Mounting: Rails Models in the Browser

The demo isn't just "React in a view"—it's Rails models running client-side.

**What Rails + react-rails does:**
```jsx
// React component calls server API
const handleSave = async (nodes) => {
  await fetch('/workflows/1', { method: 'PATCH', body: JSON.stringify({ nodes }) });
  // Offline? Error. No server = no save.
}
```

**What Juntos + RBX does:**
```ruby
# Same model code runs in browser
handleSave = ->(nodes) {
  nodes.each do |node_data|
    node = Node.find(node_data.id)
    node.update(position_x: node_data.position.x, position_y: node_data.position.y)
    # Saves to IndexedDB - works offline
  end
}
```

The `Node.update` runs transpiled model code—validations, callbacks, persistence—whether on server, browser, or mobile. Offline editing works out of the box.

**Demo focus:** Offline-capable workflow editing with React Flow.

**Prose potential:** Multi-device sync when connectivity returns (future work, not in initial demo).

## Demo: Workflow Builder

### What It Does

- Create workflows with draggable nodes
- Connect nodes with edges (draw lines between them)
- Save to database, sync across devices
- Works: browser, Capacitor (mobile), Electron (desktop)

### Create Script

```bash
curl -sL https://raw.githubusercontent.com/ruby2js/ruby2js/master/test/workflow/create-workflow | bash
cd workflow
bin/juntos dev -d dexie
```

~350 lines. Same pattern as blog (190), chat (250), photo_gallery (310).

### File Structure

```
app/
  models/
    workflow.rb              # has_many :nodes, :edges
    node.rb                  # position_x, position_y, label, node_type
    edge.rb                  # source_node_id, target_node_id

  controllers/
    workflows_controller.rb  # CRUD for workflows
    nodes_controller.rb      # API: create, update, destroy
    edges_controller.rb      # API: create, destroy

  views/
    workflows/
      index.html.erb         # ERB: list of workflows
      show.rbx               # RBX: React Flow canvas
      _workflow.html.erb     # ERB: partial

  components/
    WorkflowCanvas.rbx       # RBX: React Flow wrapper

config/
  routes.rb

db/
  seeds.rb                   # Sample workflow
```

### Key Files

#### Model: `app/models/workflow.rb`

```ruby
class Workflow < ApplicationRecord
  has_many :nodes, dependent: :destroy
  has_many :edges, dependent: :destroy

  validates :name, presence: true
end
```

#### Model: `app/models/node.rb`

```ruby
class Node < ApplicationRecord
  belongs_to :workflow

  validates :position_x, :position_y, presence: true
end
```

#### View: `app/views/workflows/index.html.erb`

```erb
<div class="container mx-auto p-4">
  <h1 class="text-2xl font-bold mb-4">Workflows</h1>

  <div class="grid gap-4">
    <%= render @workflows %>
  </div>

  <%= link_to "New Workflow", new_workflow_path,
      class: "bg-blue-600 text-white px-4 py-2 rounded" %>
</div>
```

Standard ERB. No React needed for a list.

#### View: `app/views/workflows/show.rbx`

```ruby
import WorkflowCanvas from 'components/WorkflowCanvas'

export default
def Show({workflow, nodes, edges})
  handleSave = ->(updatedNodes, updatedEdges) {
    fetch("/workflows/#{workflow.id}",
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ nodes: updatedNodes, edges: updatedEdges })
    )
  }

  %x{
    <div className="container mx-auto p-4">
      <h1 className="text-2xl font-bold mb-4">{workflow.name}</h1>
      <WorkflowCanvas
        initialNodes={nodes}
        initialEdges={edges}
        onSave={handleSave}
      />
    </div>
  }
end
```

RBX because React Flow requires React.

#### Component: `app/components/WorkflowCanvas.rbx`

```ruby
import ReactFlow, {
  Background,
  Controls,
  useNodesState,
  useEdgesState,
  addEdge
} from 'reactflow'
import 'reactflow/dist/style.css'

export default
def WorkflowCanvas({initialNodes, initialEdges, onSave})
  nodes, setNodes, onNodesChange = useNodesState(initialNodes)
  edges, setEdges, onEdgesChange = useEdgesState(initialEdges)

  handleConnect = ->(connection) {
    setEdges(->(eds) { addEdge(connection, eds) })
  }

  handleSave = ->() { onSave(nodes, edges) }

  %x{
    <div style={{ width: '100%', height: '500px' }}>
      <ReactFlow
        nodes={nodes}
        edges={edges}
        onNodesChange={onNodesChange}
        onEdgesChange={onEdgesChange}
        onConnect={handleConnect}
        fitView
      >
        <Background />
        <Controls />
      </ReactFlow>
      <button
        onClick={handleSave}
        className="mt-4 bg-green-600 text-white px-4 py-2 rounded"
      >
        Save
      </button>
    </div>
  }
end
```

### Line Count Estimate

| File | Lines |
|------|-------|
| Script scaffolding | ~100 |
| Models (3) | ~30 |
| Controllers (3) | ~80 |
| Views (2 ERB + 1 RBX) | ~60 |
| Component (RBX) | ~50 |
| Routes | ~15 |
| Seeds | ~25 |
| **Total** | **~360** |

## Cross-Platform Support

| Target | Works | Notes |
|--------|-------|-------|
| Browser | Yes | Client-only, IndexedDB |
| Capacitor (iOS/Android) | Yes | Touch drag/connect works |
| Electron (desktop) | Yes | Full mouse support |
| Node.js | Yes | Server + API |
| Cloudflare/Vercel Edge | Yes | Server + API (D1/Neon) |

Edge functions are just servers reorganized as functions—they take requests and return responses. The interactive React Flow canvas renders client-side; the server (edge or otherwise) handles CRUD. Same code, different deployment target.

## Blog Post: 3398

### Title Options

- "Rails Meets the React Ecosystem"
- "When Hotwire Isn't Enough"
- "RBX: Ruby's Bridge to React"

### Narrative Arc

1. **Incredulous claim**: "The React component isn't calling a Rails API. It's calling Rails models—that happen to be running in your browser."

2. **Context**: Hotwire handles most interactivity. Fizzy proves you can build Kanban with 6% JavaScript. But some things need React—and when they do, you shouldn't have to leave Ruby or sacrifice offline capability.

3. **The escape hatch**: RBX files. When you need React, write `.rbx`. When you don't, stay with ERB. Mix freely in the same app.

4. **The demo**: Visual workflow builder. Drag nodes. Draw connections. Toggle airplane mode. *Keep editing*—saves to IndexedDB. Same models, same validations, running client-side.

5. **The pattern**:
   - Blog: 190 lines (CRUD)
   - Chat: 250 lines (real-time)
   - Photo gallery: 310 lines (native APIs)
   - Workflow: 360 lines (React ecosystem + offline)

6. **The future** (prose, not demo): Multi-device sync. Edit on your phone, changes appear on desktop when connectivity returns. The architecture supports it; implementation is future work.

7. **The punchline**: "React Flow handles the canvas. Juntos handles everything else—models, validations, offline persistence. One Ruby codebase. No server required."

### Key Points

- Three views in the demo: two ERB, one RBX. Use the right tool for each.
- React Flow is ~50 lines of RBX. The library does the hard work.
- Same models, same controllers, same patterns. Just a different view format.
- Touch works on mobile. No extra code.

## Implementation Phases

### Phase 1: RBX Foundation (from UNIFIED_VIEWS.md)

- [ ] `.rbx` file detection in builder
- [ ] RBX transpilation (Ruby2JS with React filter)
- [ ] Import resolution for npm packages
- [ ] Component directory convention (`app/components/`)

### Phase 2: React Flow Integration

- [ ] Add reactflow to package.json template
- [ ] Verify CSS import handling
- [ ] Test touch events on Capacitor
- [ ] Test mouse events on Electron

### Phase 3: Create Script

- [ ] Write `test/workflow/create-workflow` script
- [ ] Models, controllers, routes
- [ ] ERB views for list/partials
- [ ] RBX view for canvas
- [ ] RBX component wrapping React Flow
- [ ] Seeds with sample workflow

### Phase 4: Documentation

- [ ] Demo page on ruby2js.com
- [ ] Blog post 3398
- [ ] Add to Juntos demos list

## Future Extensions

### Action Text with Tiptap

The workflow demo proves RBX works. A natural follow-up is Action Text:

```ruby
class Article < ApplicationRecord
  has_rich_text :body
end
```

With Tiptap as the editor, optionally with Yjs collaboration. The abstraction could support multiple editors, but Tiptap is the clear default for Juntos (works everywhere, collaboration built-in).

### Other React Ecosystem Demos

- **Data visualization**: Recharts dashboard with drill-down
- **Design canvas**: Fabric.js or Konva for drawing tools
- **Node editor**: More sophisticated React Flow with custom node types

Each follows the same pattern: RBX wraps a React library, integrates with Rails models, runs on all Juntos targets.

## Success Criteria

1. `create-workflow` script produces working app in ~360 lines
2. Demo works on browser, Capacitor, Electron
3. RBX component is <50 lines
4. Blog post tells coherent story about ecosystem access
5. Clear contrast with Hotwire-only approach
