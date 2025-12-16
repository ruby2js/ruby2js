# Comment model
class Comment < ApplicationRecord
  # belongs_to :article

  def article
    Article.find(@attributes['article_id'])
  end

  def validate
    validates_presence_of :commenter
    validates_presence_of :body
  end

  # Attribute accessors
  def commenter
    @attributes['commenter']
  end

  def commenter=(value)
    @attributes['commenter'] = value
  end

  def body
    @attributes['body']
  end

  def body=(value)
    @attributes['body'] = value
  end

  def article_id
    @attributes['article_id']
  end

  def article_id=(value)
    @attributes['article_id'] = value
  end

  def status
    @attributes['status']
  end

  def status=(value)
    @attributes['status'] = value
  end

  def created_at
    @attributes['created_at']
  end
end
