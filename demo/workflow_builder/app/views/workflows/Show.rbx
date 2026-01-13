import React from 'react'
import WorkflowCanvas from 'components/WorkflowCanvas'
import [Node], from: '../../models/node.js'
import [Edge], from: '../../models/edge.js'

export default
def Show(workflow:)
  # Get nodes and edges from workflow (preloaded by controller)
  nodes = workflow.nodes
  edges = workflow.edges

  # Convert Rails nodes to React Flow format
  flow_nodes = nodes.map do |node|
    {
      id: node.id.to_s,
      type: 'default',
      position: { x: node.position_x, y: node.position_y },
      data: { label: node.label }
    }
  end

  # Convert Rails edges to React Flow format
  flow_edges = edges.map do |edge|
    {
      id: edge.id.to_s,
      source: edge.source_node_id.to_s,
      target: edge.target_node_id.to_s
    }
  end

  handle_save = ->(updated_nodes) {
    # Update node positions directly in the database
    updated_nodes.each do |node_data|
      Node.find(node_data.id.to_i).then(->(node) {
        node.update(position_x: node_data.position.x, position_y: node_data.position.y)
      })
    end
  }

  handle_add_node = ->(position) {
    # Create node directly in the database
    Node.create(
      label: "New Node",
      node_type: "default",
      position_x: position.x,
      position_y: position.y,
      workflow_id: workflow.id
    )
  }

  handle_add_edge = ->(source_id, target_id) {
    # Create edge directly in the database
    Edge.create(
      source_node_id: source_id.to_i,
      target_node_id: target_id.to_i,
      workflow_id: workflow.id
    )
  }

  %x{
    <div className="container mx-auto px-4 py-8">
      <div className="flex justify-between items-center mb-4">
        <h1 className="text-3xl font-bold">{workflow.name}</h1>
        <a href="/workflows" className="text-blue-600 hover:underline">
          Back to Workflows
        </a>
      </div>
      <div data-controller="workflow-channel" data-workflow-channel-id-value={workflow.id}>
        <WorkflowCanvas
          initialNodes={flow_nodes}
          initialEdges={flow_edges}
          onSave={handle_save}
          onAddNode={handle_add_node}
          onAddEdge={handle_add_edge}
        />
      </div>
    </div>
  }
end
