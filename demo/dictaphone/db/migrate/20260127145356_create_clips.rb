class CreateClips < ActiveRecord::Migration[8.1]
  def change
    create_table :clips do |t|
      t.string :name
      t.text :transcript
      t.float :duration

      t.timestamps
    end
  end
end
