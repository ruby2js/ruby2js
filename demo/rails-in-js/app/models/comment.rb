import [ApplicationRecord], './application_record.js'

# Comment model
# Note: Article is referenced at runtime, not imported to avoid circular dependency
export class Comment < ApplicationRecord
  def self.table_name
    'comments'
  end

  # belongs_to :article
  def article
    Article.find(self.attributes['article_id'])
  end

  def validate
    self.validates_presence_of(:commenter)
    self.validates_presence_of(:body)
  end

  # Attribute accessors - use self. to access parent getters
  def commenter
    self.attributes['commenter']
  end

  def commenter=(value)
    self.attributes['commenter'] = value
  end

  def body
    self.attributes['body']
  end

  def body=(value)
    self.attributes['body'] = value
  end

  def article_id
    self.attributes['article_id']
  end

  def article_id=(value)
    self.attributes['article_id'] = value
  end

  def status
    self.attributes['status']
  end

  def status=(value)
    self.attributes['status'] = value
  end

  def created_at
    self.attributes['created_at']
  end
end
