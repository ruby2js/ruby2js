class CreateEdges < ActiveRecord::Migration[8.1]
  def change
    create_table :edges do |t|
      t.references :workflow, null: false, foreign_key: true
      t.integer :source_node_id
      t.integer :target_node_id

      t.timestamps
    end
  end
end
