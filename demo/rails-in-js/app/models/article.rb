# Article model
class Article < ApplicationRecord
  # has_many :comments, dependent: :destroy

  def comments
    Comment.where(article_id: @id)
  end

  def validate
    validates_presence_of :title
    validates_presence_of :body
    validates_length_of :body, minimum: 10
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
    comments.each(&:destroy)
    super
  end
end
