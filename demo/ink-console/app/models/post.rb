class Post < ApplicationRecord
  belongs_to :user
  has_many :comments

  scope :published, -> { where(published: true) }
  scope :drafts, -> { where(published: false) }
end
