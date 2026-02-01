class Clip < ApplicationRecord
  has_one_attached :audio

  validates :name, presence: true

  broadcasts_to -> { "clips" }, inserts_by: :prepend
end
