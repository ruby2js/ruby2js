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
