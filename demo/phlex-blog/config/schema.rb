# Database schema - idiomatic Rails
ActiveRecord::Schema.define do
  create_table "posts" do |t|
    t.string "title", null: false
    t.text "body"
    t.string "author", default: "Anonymous"
    t.timestamps
  end
end
