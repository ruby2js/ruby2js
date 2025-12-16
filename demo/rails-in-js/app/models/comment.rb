import ApplicationRecord from './application_record.js'

# Comment model
# Note: Article is referenced at runtime, not imported to avoid circular dependency
export class Comment < ApplicationRecord
  def self.table_name
    'comments'
  end

  # belongs_to :article
  def article
    Article.find(@attributes['article_id'])
  end

  def validate
    self.validates_presence_of(:commenter)
    self.validates_presence_of(:body)
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
