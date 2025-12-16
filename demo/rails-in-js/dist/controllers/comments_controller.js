// Comments controller - handles comment CRUD (nested under articles)
class CommentsController extends ApplicationController {
  #article;
  #comment;

  // POST /articles/:article_id/comments
  get create() {
    this.#comment = new Comment(this.#comment_params);
    this.#comment.article_id = this.#article.id;
    this.#comment.save;
    return redirect_to(this.#article)
  };

  // DELETE /articles/:article_id/comments/:id
  get destroy() {
    this.#comment = Comment.where({article_id: this.#article.id}).find(c => (
      c.id == parseInt(params.id)
    ));

    if (this.#comment) this.#comment.destroy;
    return redirect_to(this.#article)
  };

  get #set_article() {
    this.#article = Article.find(params.article_id);
    return this.#article
  };

  get #comment_params() {
    return params.require("comment").permit(
      "commenter",
      "body",
      "status"
    )
  }
};

CommentsController.before_action("set_article")