class Edge < ApplicationRecord
  belongs_to :workflow
  belongs_to :source_node, class_name: 'Node'
  belongs_to :target_node, class_name: 'Node'

  # Broadcast JSON events for real-time collaboration
  after_create_commit do
    broadcast_json_to "workflow_#{workflow_id}", "edge_created"
  end

  after_destroy_commit do
    broadcast_json_to "workflow_#{workflow_id}", "edge_destroyed"
  end
end
