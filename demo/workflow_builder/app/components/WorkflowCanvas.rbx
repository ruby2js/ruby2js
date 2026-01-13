import React from 'react'
import ReactFlow, [Background, Controls, MiniMap, useNodesState, useEdgesState, addEdge], from: 'reactflow'
import 'reactflow/dist/style.css'

export default
def WorkflowCanvas(initialNodes:, initialEdges:, onSave:, onAddNode:, onAddEdge:)
  nodes, setNodes, onNodesChange = useNodesState(initialNodes)
  edges, setEdges, onEdgesChange = useEdgesState(initialEdges)

  # Handle new connections between nodes
  handle_connect = ->(connection) {
    onAddEdge(connection.source, connection.target).then(->(edge) {
      setEdges(->(eds) {
        addEdge({ **connection, id: edge.id.to_s }, eds)
      })
    })
  }

  # Save positions after drag ends
  handle_node_drag_stop = ->(_event, _node) {
    # Collect all node positions
    positions = nodes.map do |n|
      { id: n.id, position: n.position }
    end
    onSave(positions)
  }

  # Double-click to add new node (use onDoubleClick instead of checking event.detail)
  handle_double_click = ->(event) {
    console.log('Double click detected', event)

    # Get click position relative to the flow
    bounds = event.target.getBoundingClientRect()
    position = {
      x: event.clientX - bounds.left,
      y: event.clientY - bounds.top
    }

    onAddNode(position).then(->(node) {
      new_node = {
        id: node.id.to_s,
        type: 'default',
        position: { x: node.position_x, y: node.position_y },
        data: { label: node.label }
      }
      setNodes(->(nds) { [*nds, new_node] })
    })
  }

  %x{
    <div style={{ width: '100%', height: '600px', border: '1px solid #ddd', borderRadius: '8px' }} onDoubleClick={handle_double_click}>
      <ReactFlow
        nodes={nodes}
        edges={edges}
        onNodesChange={onNodesChange}
        onEdgesChange={onEdgesChange}
        onConnect={handle_connect}
        onNodeDragStop={handle_node_drag_stop}
        zoomOnDoubleClick={false}
        fitView
      >
        <Background color="#aaa" gap={16} />
        <Controls />
        <MiniMap />
      </ReactFlow>
      <p className="text-gray-500 text-sm mt-2 text-center">
        Double-click to add nodes. Drag from node handles to connect.
      </p>
    </div>
  }
end
