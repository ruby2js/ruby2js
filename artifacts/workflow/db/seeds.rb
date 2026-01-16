# Sample workflow for the demo
return if Workflow.count > 0

workflow = Workflow.create!(name: "User Registration Flow")

# Create nodes
start_node = workflow.nodes.create!(
  label: "Start",
  node_type: "input",
  position_x: 250,
  position_y: 0
)

email_node = workflow.nodes.create!(
  label: "Enter Email",
  node_type: "default",
  position_x: 100,
  position_y: 100
)

password_node = workflow.nodes.create!(
  label: "Create Password",
  node_type: "default",
  position_x: 400,
  position_y: 100
)

verify_node = workflow.nodes.create!(
  label: "Verify Email",
  node_type: "default",
  position_x: 250,
  position_y: 200
)

complete_node = workflow.nodes.create!(
  label: "Registration Complete",
  node_type: "output",
  position_x: 250,
  position_y: 300
)

# Create edges
workflow.edges.create!(source_node: start_node, target_node: email_node)
workflow.edges.create!(source_node: start_node, target_node: password_node)
workflow.edges.create!(source_node: email_node, target_node: verify_node)
workflow.edges.create!(source_node: password_node, target_node: verify_node)
workflow.edges.create!(source_node: verify_node, target_node: complete_node)

puts "Created workflow '#{workflow.name}' with #{workflow.nodes.count} nodes and #{workflow.edges.count} edges"
