# Path helpers for URL generation
# Mimics Rails route helpers

export module PathHelpers
  def self.articles_path
    '/articles'
  end

  def self.article_path(article)
    id = extract_id(article)
    "/articles/#{id}"
  end

  def self.new_article_path
    '/articles/new'
  end

  def self.edit_article_path(article)
    id = extract_id(article)
    "/articles/#{id}/edit"
  end

  # Comments paths (nested under articles)
  def self.article_comments_path(article)
    id = extract_id(article)
    "/articles/#{id}/comments"
  end

  def self.article_comment_path(article, comment)
    article_id = extract_id(article)
    comment_id = extract_id(comment)
    "/articles/#{article_id}/comments/#{comment_id}"
  end

  def self.extract_id(obj)
    # If obj has an id property, use it; otherwise obj is the id
    (obj && obj.id) || obj
  end

  # Root path
  def self.root_path
    '/'
  end
end
