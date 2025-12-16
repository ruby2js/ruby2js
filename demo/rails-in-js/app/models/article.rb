import ApplicationRecord from './application_record.js'
import Comment from './comment.js'

# Article model
export class Article < ApplicationRecord
  def self.table_name
    'articles'
  end

  # has_many :comments, dependent: :destroy
  def comments
    Comment.where(article_id: @id)
  end

  def validate
    self.validates_presence_of(:title)
    self.validates_presence_of(:body)
    self.validates_length_of(:body, minimum: 10)
  end

  # Attribute accessors
  def title
    @attributes['title']
  end

  def title=(value)
    @attributes['title'] = value
  end

  def body
    @attributes['body']
  end

  def body=(value)
    @attributes['body'] = value
  end

  def created_at
    @attributes['created_at']
  end

  def updated_at
    @attributes['updated_at']
  end

  # Destroy associated comments
  def destroy
    comments.each { |c| c.destroy }
    super
  end
end
