# Comments controller - SPA-friendly version
# Handles comment CRUD (nested under articles)

import [Comment], '../models/comment.js'

export module CommentsController
  def self.create(article_id, commenter, body)
    comment = Comment.create({
      article_id: article_id,
      commenter: commenter,
      body: body
    })
    { success: true, article_id: article_id }
  end

  def self.destroy(article_id, comment_id)
    comments = Comment.where({ article_id: article_id })
    comment = comments.find { |c| c.id == comment_id }
    comment.destroy if comment
    { success: true, article_id: article_id }
  end
end
