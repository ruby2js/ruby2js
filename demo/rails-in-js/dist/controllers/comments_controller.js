// Comments controller - idiomatic Rails
import { Article } from "../models/article.js";

export const CommentsController = (() => {
  function create(article_id, params) {
    let article = Article.find(article_id);
    let comment = article.comments.create(params);
    return {redirect: `/articles/${article.id}`}
  };

  function destroy(article_id, id) {
    let article = Article.find(article_id);
    let comment = article.comments.find(id);
    comment.destroy;
    return {redirect: `/articles/${article.id}`}
  };

  return {create, destroy}
})()
//# sourceMappingURL=comments_controller.js.map