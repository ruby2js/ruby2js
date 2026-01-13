import React, [useState, useEffect, useCallback], from: 'react'
# React Flow is browser-only (visual canvas library)
import ReactFlow, [Background, Controls, MiniMap, useNodesState, useEdgesState, addEdge], from: 'reactflow' # Pragma: browser
import 'reactflow/dist/style.css' # Pragma: browser
import [useJsonStream], from: '../../lib/JsonStreamProvider.js'

export default
def WorkflowCanvas(initialNodes:, initialEdges:, onSave:, onAddNode:, onAddEdge:, onDeleteNode:, onUpdateNode:)
  # SSR-safe: only render canvas when ReactFlow is available
  unless defined?(ReactFlow)
    return %x{
      <div style={{ width: '100%', height: '600px', border: '1px solid #ddd', borderRadius: '8px' }}
           className="flex items-center justify-center bg-gray-100">
        <p className="text-gray-500">Workflow canvas requires browser environment</p>
      </div>
    }
  end

  nodes, setNodes, onNodesChange = useNodesState(initialNodes)
  edges, setEdges, onEdgesChange = useEdgesState(initialEdges)
  reactFlowInstance, setReactFlowInstance = useState(nil)

  # Get JSON stream messages from context provider
  stream = useJsonStream()

  # Handle incoming broadcast messages for real-time collaboration
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
            {
              **n,
              position: { x: payload.data.position_x, y: payload.data.position_y },
              data: { label: payload.data.label }
            }
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

  # Double-click on pane to add new node (uses viewport-aware coordinates)
  handle_pane_double_click = useCallback(->(event) {
    return unless reactFlowInstance
    # Convert screen coordinates to flow coordinates (accounts for zoom/pan)
    position = reactFlowInstance.screenToFlowPosition({
      x: event.clientX,
      y: event.clientY
    })

    onAddNode(position).then(->(node) {
      new_node = {
        id: node.id.to_s,
        type: 'default',
        position: { x: node.position_x, y: node.position_y },
        data: { label: node.label }
      }
      setNodes(->(nds) { [*nds, new_node] })
    })
  }, [reactFlowInstance, onAddNode])

  # Delete selected nodes via keyboard (Backspace/Delete)
  handle_nodes_delete = ->(deleted_nodes) {
    deleted_nodes.each do |node|
      onDeleteNode(node.id)
    end
  }

  # Double-click on node to edit label
  handle_node_double_click = ->(_event, node) {
    new_label = prompt("Edit node label:", node.data.label)
    if new_label && new_label != node.data.label
      onUpdateNode(node.id, new_label)
      # Optimistic update - real-time broadcast will confirm
      setNodes(->(nds) {
        nds.map do |n|
          if n.id == node.id
            { **n, data: { **n.data, label: new_label } }
          else
            n
          end
        end
      })
    end
  }

  %x{
    <div style={{ width: '100%', height: '600px', border: '1px solid #ddd', borderRadius: '8px' }}>
      <ReactFlow
        nodes={nodes}
        edges={edges}
        onNodesChange={onNodesChange}
        onEdgesChange={onEdgesChange}
        onConnect={handle_connect}
        onNodeDragStop={handle_node_drag_stop}
        onNodesDelete={handle_nodes_delete}
        onNodeDoubleClick={handle_node_double_click}
        onPaneDoubleClick={handle_pane_double_click}
        onInit={setReactFlowInstance}
        zoomOnDoubleClick={false}
        fitView
      >
        <Background color="#aaa" gap={16} />
        <Controls />
        <MiniMap />
      </ReactFlow>
      <p className="text-gray-500 text-sm mt-2 text-center">
        Double-click canvas to add nodes. Double-click node to edit label. Select + Delete to remove. Drag handles to connect.
      </p>
    </div>
  }
end
