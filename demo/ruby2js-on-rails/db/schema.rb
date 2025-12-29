# This file is auto-generated from the current state of the database.
# It represents the database schema for Ruby2JS-on-Rails demo.

ActiveRecord::Schema.define(version: 2024_01_01_000000) do
  create_table "articles", force: :cascade do |t|
    t.string "title"
    t.text "body"
    t.timestamps
  end
end
