import [ApplicationRecord], './application_record.js'
import [Comment], './comment.js'

# Article model
export class Article < ApplicationRecord
  def self.table_name
    'articles'
  end

  # has_many :comments, dependent: :destroy
  def comments
    Comment.where(article_id: self.id)
  end

  def validate
    self.validates_presence_of(:title)
    self.validates_presence_of(:body)
    self.validates_length_of(:body, minimum: 10)
  end

  # Attribute accessors - use self. to access parent getters
  def title
    self.attributes['title']
  end

  def title=(value)
    self.attributes['title'] = value
  end

  def body
    self.attributes['body']
  end

  def body=(value)
    self.attributes['body'] = value
  end

  def created_at
    self.attributes['created_at']
  end

  def updated_at
    self.attributes['updated_at']
  end

  # Destroy associated comments
  def destroy
    comments.each { |c| c.destroy }
    super
  end
end
