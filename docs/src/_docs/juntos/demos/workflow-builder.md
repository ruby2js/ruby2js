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
- **Stimulus bridge** — WebSocket subscription via Stimulus controller
- **Real-time sync** — Multiple users see changes instantly

Unlike Turbo Streams (which broadcast HTML), this demo uses JSON events that React components can use to update their internal state.

## The Challenge

Turbo Streams work great for server-rendered HTML, but React manages its own DOM. Broadcasting HTML fragments would conflict with React's reconciliation. The solution:

1. **Models broadcast JSON events** — not HTML
2. **Stimulus handles WebSocket subscription** — Rails-like pattern
3. **React listens for custom events** — updates state accordingly

## The Code

### Node Model with JSON Broadcasting

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

### Stimulus Controller for WebSocket

```ruby
# app/javascript/controllers/workflow_channel_controller.rb
class WorkflowChannelController < Stimulus::Controller
  def connect
    @channel = "workflow_#{idValue}"
    @ws = WebSocket.new("ws://#{window.location.host}/cable")

    @ws.onopen = -> {
      @ws.send!(JSON.stringify({ type: 'subscribe', stream: @channel }))
      console.log("WorkflowChannel: subscribed to #{@channel}")
    }

    @ws.onmessage = ->(event) {
      msg = JSON.parse(event.data)
      return unless msg.type == 'message'
      payload = JSON.parse(msg.message)
      received(payload)
    }

    @ws.onerror = ->(error) {
      console.error("WorkflowChannel error:", error)
    }

    @ws.onclose = -> {
      console.log("WorkflowChannel: disconnected from #{@channel}")
    }
  end

  def disconnect
    if @ws
      @ws.send!(JSON.stringify({ type: 'unsubscribe', stream: @channel }))
      @ws.close()
      @ws = nil
    end
  end

  def received(data)
    # Dispatch custom event for React to handle
    event = CustomEvent.new("workflow:broadcast", { detail: data, bubbles: true })
    element.dispatchEvent(event)
  end
end
```

### View with Stimulus Controller

```ruby
# app/views/workflows/Show.rbx
<div data-controller="workflow-channel" data-workflow-channel-id-value={workflow.id}>
  <WorkflowCanvas
    initialNodes={flow_nodes}
    initialEdges={flow_edges}
    onSave={handle_save}
    onAddNode={handle_add_node}
    onAddEdge={handle_add_edge}
  />
</div>
```

### React Component Listening for Events

```ruby
# app/components/WorkflowCanvas.rbx
import React, [useState, useCallback, useRef, useEffect], from: 'react'
import ReactFlow, [...], from: 'reactflow' # Pragma: browser

export default
def WorkflowCanvas(initialNodes:, initialEdges:, onSave:, onAddNode:, onAddEdge:)
  nodes, setNodes, onNodesChange = useNodesState(initialNodes)
  edges, setEdges, onEdgesChange = useEdgesState(initialEdges)
  containerRef = useRef(nil)

  # Listen for broadcast events from Stimulus controller
  useEffect(-> {
    container = containerRef.current
    return unless container

    handle_broadcast = ->(event) {
      payload = event.detail

      case payload.type
      when 'node_created'
        new_node = {
          id: payload.data.id.to_s,
          type: 'default',
          position: { x: payload.data.position_x, y: payload.data.position_y },
          data: { label: payload.data.label }
        }
        setNodes(->(prev) { [...prev, new_node] })

      when 'node_updated'
        setNodes(->(prev) {
          prev.map { |n|
            if n.id == payload.id.to_s
              { **n, position: { x: payload.data.position_x, y: payload.data.position_y } }
            else
              n
            end
          }
        })

      when 'node_destroyed'
        setNodes(->(prev) { prev.filter { |n| n.id != payload.id.to_s } })

      when 'edge_created'
        new_edge = {
          id: payload.data.id.to_s,
          source: payload.data.source_node_id.to_s,
          target: payload.data.target_node_id.to_s
        }
        setEdges(->(prev) { [...prev, new_edge] })

      when 'edge_destroyed'
        setEdges(->(prev) { prev.filter { |e| e.id != payload.id.to_s } })
      end
    }

    container.addEventListener('workflow:broadcast', handle_broadcast)
    -> { container.removeEventListener('workflow:broadcast', handle_broadcast) }
  }, [])

  # ... rest of component (drag handlers, etc.)
end
```

## How It Works

1. **User creates a node** — double-click on canvas
2. **React calls `onAddNode`** — creates Node in database
3. **Model callback fires** — `after_create_commit` broadcasts JSON
4. **WebSocket delivers** — to all subscribers on the channel
5. **Stimulus receives** — dispatches `workflow:broadcast` event
6. **React handles** — updates state, re-renders

The key insight: Stimulus handles the "Rails-like" WebSocket subscription, while React handles its own state. They communicate via DOM events.

## Turbo Streams vs JSON Broadcasting

| Aspect | Turbo Streams | JSON Broadcasting |
|--------|---------------|-------------------|
| **Payload** | HTML fragments | JSON data |
| **DOM update** | Turbo handles | React handles |
| **Best for** | Server-rendered views | React/JS components |
| **Method** | `broadcast_append_to` | `broadcast_json_to` |

Use Turbo Streams for ERB views. Use JSON broadcasting for React components.

## Real-Time Collaboration

With JSON broadcasting, multiple users can:

- See new nodes appear instantly
- Watch nodes move as others drag them
- See edges created between nodes
- Observe deletions in real-time

Each browser maintains its own React state, but the state stays synchronized via WebSocket broadcasts.

## What This Demo Shows

### JSON Broadcasting Pattern

- `broadcast_json_to` — send JSON instead of HTML
- Custom events — bridge Stimulus and React
- State synchronization — multiple clients stay in sync

### React Integration

- Third-party React libraries (React Flow)
- Ruby syntax for React components (`.rbx` files)
- `useEffect` for event listeners
- State management with `useState`

### Stimulus as WebSocket Client

- WebSocket subscription in Stimulus
- Dispatch custom events to React
- Clean disconnect handling

## Next Steps

- Read [Hotwire](/docs/juntos/hotwire) for JSON broadcasting reference
- Try the [Chat Demo](/docs/juntos/demos/chat) for Turbo Streams patterns
- See [Architecture](/docs/juntos/architecture) for how React components work
