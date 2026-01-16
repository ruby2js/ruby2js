class CreateNodes < ActiveRecord::Migration[8.1]
  def change
    create_table :nodes do |t|
      t.references :workflow, null: false, foreign_key: true
      t.string :label
      t.string :node_type
      t.float :position_x
      t.float :position_y

      t.timestamps
    end
  end
end
