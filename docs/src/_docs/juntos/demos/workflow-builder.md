---
order: 665
title: Workflow Builder Demo
top_section: Juntos
category: juntos/demos
hide_in_toc: true
---

A visual workflow editor demonstrating React component integration with Rails patterns and real-time collaboration via JSON broadcasting.

{% toc %}

## Overview

This demo shows how to integrate third-party React libraries (React Flow) with Juntos while maintaining Rails-like patterns:

- **React Flow** — Node-based visual editor for workflows
- **JSON broadcasting** — `broadcast_json_to` for React state updates
- **React Context** — `JsonStreamProvider` (from ruby2js-rails) for subscription management
- **Real-time sync** — Multiple users see changes instantly
- **Multi-target** — Works on both browser (BroadcastChannel) and node (WebSocket) targets

Unlike Turbo Streams (which broadcast HTML), this demo uses JSON events that React components can use to update their internal state.

## The Challenge

Turbo Streams work great for server-rendered HTML, but React manages its own DOM. Broadcasting HTML fragments would conflict with React's reconciliation. The solution:

1. **Models broadcast JSON events** — not HTML
2. **React Context handles subscription** — automatic transport selection
3. **Components use hooks** — idiomatic React pattern

## The Code

### Node Model with JSON Broadcasting

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["model", "esm", "functions"]
}'></div>

```ruby
# app/models/node.rb
class Node < ApplicationRecord
  belongs_to :workflow

  validates :position_x, :position_y, presence: true
  validates :label, presence: true

  # Broadcast JSON events for real-time collaboration
  after_create_commit do
    broadcast_json_to "workflow_#{workflow_id}", "node_created"
  end

  after_update_commit do
    broadcast_json_to "workflow_#{workflow_id}", "node_updated"
  end

  after_destroy_commit do
    broadcast_json_to "workflow_#{workflow_id}", "node_destroyed"
  end
end
```

The `broadcast_json_to` method sends:

```json
{
  "type": "node_created",
  "model": "Node",
  "id": 42,
  "data": {"id": 42, "label": "New Node", "position_x": 100, "position_y": 200, ...}
}
```

### Edge Model

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["model", "esm", "functions"]
}'></div>

```ruby
# app/models/edge.rb
class Edge < ApplicationRecord
  belongs_to :workflow
  belongs_to :source_node, class_name: 'Node'
  belongs_to :target_node, class_name: 'Node'

  after_create_commit do
    broadcast_json_to "workflow_#{workflow_id}", "edge_created"
  end

  after_destroy_commit do
    broadcast_json_to "workflow_#{workflow_id}", "edge_destroyed"
  end
end
```

### JsonStreamProvider Component

The `JsonStreamProvider` is included in the ruby2js-rails package. It handles WebSocket (node target) or BroadcastChannel (browser target) automatically:

```ruby
# Import from lib/ (copied during build) - use relative path from your file
# From app/views/workflows/Show.jsx.rb:
import JsonStreamProvider from '../../../lib/JsonStreamProvider.js'

# From app/components/WorkflowCanvas.jsx.rb:
import [useJsonStream], from: '../../lib/JsonStreamProvider.js'
```

**Props:**
- `stream` — Channel name to subscribe to (e.g., `"workflow_123"`)
- `endpoint` — WebSocket path (default: `"/cable"`)
- `children` — React children to render

**Hook return value:**
- `lastMessage` — Most recent JSON payload
- `connected` — Boolean connection status
- `stream` — The stream name

### View with Provider

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["react", "esm", "functions"]
}'></div>

```ruby
# app/views/workflows/Show.jsx.rb
import JsonStreamProvider from '../../../lib/JsonStreamProvider.js'
import WorkflowCanvas from 'components/WorkflowCanvas'

export default
def Show(workflow:)
  %x{
    <div className="container mx-auto px-4 py-8">
      <h1 className="text-3xl font-bold">{workflow.name}</h1>
      <JsonStreamProvider stream={"workflow_#{workflow.id}"}>
        <WorkflowCanvas
          initialNodes={flow_nodes}
          initialEdges={flow_edges}
          onSave={handle_save}
          onAddNode={handle_add_node}
          onAddEdge={handle_add_edge}
        />
      </JsonStreamProvider>
    </div>
  }
end
```

### React Component Using the Hook

<div data-controller="combo" data-options='{
  "eslevel": 2022,
  "filters": ["react", "esm", "functions"]
}'></div>

```ruby
# app/components/WorkflowCanvas.jsx.rb
import React, [useEffect], from: 'react'
import ReactFlow, [...], from: 'reactflow' # Pragma: browser
import [useJsonStream], from: '../../lib/JsonStreamProvider.js'

export default
def WorkflowCanvas(initialNodes:, initialEdges:, onSave:, onAddNode:, onAddEdge:)
  nodes, setNodes, onNodesChange = useNodesState(initialNodes)
  edges, setEdges, onEdgesChange = useEdgesState(initialEdges)

  # Get JSON stream from context
  stream = useJsonStream()

  # Handle incoming broadcast messages
  useEffect(-> {
    return unless stream.lastMessage
    payload = stream.lastMessage

    case payload.type
    when 'node_created'
      new_node = {
        id: payload.id.to_s,
        type: 'default',
        position: { x: payload.data.position_x, y: payload.data.position_y },
        data: { label: payload.data.label }
      }
      setNodes(->(nds) { [*nds, new_node] })

    when 'node_updated'
      setNodes(->(nds) {
        nds.map do |n|
          if n.id == payload.id.to_s
            { **n, position: { x: payload.data.position_x, y: payload.data.position_y } }
          else
            n
          end
        end
      })

    when 'node_destroyed'
      setNodes(->(nds) { nds.filter(->(n) { n.id != payload.id.to_s }) })

    when 'edge_created'
      new_edge = {
        id: payload.id.to_s,
        source: payload.data.source_node_id.to_s,
        target: payload.data.target_node_id.to_s
      }
      setEdges(->(eds) { [*eds, new_edge] })

    when 'edge_destroyed'
      setEdges(->(eds) { eds.filter(->(e) { e.id != payload.id.to_s }) })
    end
  }, [stream.lastMessage])

  # ... rest of component (drag handlers, etc.)
end
```

## How It Works

1. **User creates a node** — double-click on canvas
2. **React calls `onAddNode`** — creates Node in database
3. **Model callback fires** — `after_create_commit` broadcasts JSON
4. **Transport delivers** — WebSocket (node) or BroadcastChannel (browser)
5. **Provider receives** — updates `lastMessage` in context
6. **useEffect triggers** — component updates state, React re-renders

The key insight: React Context handles subscription management, while the provider abstracts the transport mechanism.

## Turbo Streams vs JSON Broadcasting

| Aspect | Turbo Streams | JSON Broadcasting |
|--------|---------------|-------------------|
| **Payload** | HTML fragments | JSON data |
| **DOM update** | Turbo handles | React handles |
| **Best for** | Server-rendered views | React/JS components |
| **Method** | `broadcast_append_to` | `broadcast_json_to` |
| **Subscription** | `turbo_stream_from` | `JsonStreamProvider` |

Use Turbo Streams for ERB views. Use JSON broadcasting for React components.

## Multi-Target Support

The `JsonStreamProvider` automatically selects the right transport:

| Target | Transport | Scope |
|--------|-----------|-------|
| **Browser** | `BroadcastChannel` | Same-origin tabs |
| **Node.js** | WebSocket | All connected clients |
| **Bun** | WebSocket | All connected clients |
| **Deno** | WebSocket | All connected clients |

This means the same React component code works in both browser-only mode (local development, offline apps) and server mode (multi-user collaboration).

## What This Demo Shows

### JSON Broadcasting Pattern

- `broadcast_json_to` — send JSON instead of HTML
- React Context — manage subscription state
- Multi-target transport — automatic WebSocket/BroadcastChannel selection

### React Integration

- Third-party React libraries (React Flow)
- Ruby syntax for React components (`.jsx.rb` files)
- Context providers and hooks
- State management with `useState`

### Real-Time Collaboration

- Multiple users see changes instantly
- Works in browser (same device) and server (across devices) modes
- No custom WebSocket code in components

## Next Steps

- Read [Hotwire](/docs/juntos/hotwire) for JSON broadcasting reference
- Try the [Chat Demo](/docs/juntos/demos/chat) for Turbo Streams patterns
- See [Architecture](/docs/juntos/architecture) for how React components work
