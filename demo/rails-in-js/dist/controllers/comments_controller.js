import { Comment } from "../models/comment.js";

// Comments controller - SPA-friendly version
// Handles comment CRUD (nested under articles)
export const CommentsController = (() => {
  function create(article_id, commenter, body) {
    let comment = Comment.create({article_id, commenter, body});
    return {success: true, article_id}
  };

  function destroy(article_id, comment_id) {
    let comments = Comment.where({article_id});
    let comment = comments.find(c => c.id == comment_id);
    if (comment) comment.destroy;
    return {success: true, article_id}
  };

  return {create, destroy}
})()