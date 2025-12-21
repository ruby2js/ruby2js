# Database schema - idiomatic Rails
ActiveRecord::Schema.define do
  create_table "articles" do |t|
    t.string "title", null: false
    t.text "body"
    t.timestamps
  end

  create_table "comments" do |t|
    t.references "article", null: false, foreign_key: true
    t.string "commenter"
    t.text "body"
    t.string "status", default: "pending"
    t.timestamps
  end
end
