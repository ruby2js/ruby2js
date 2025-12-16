# Comments controller - handles comment CRUD (nested under articles)
class CommentsController < ApplicationController
  before_action :set_article

  # POST /articles/:article_id/comments
  def create
    @comment = Comment.new(comment_params)
    @comment.article_id = @article.id
    @comment.save
    redirect_to @article
  end

  # DELETE /articles/:article_id/comments/:id
  def destroy
    @comment = Comment.where(article_id: @article.id).find { |c| c.id == params[:id].to_i }
    @comment.destroy if @comment
    redirect_to @article
  end

  private

  def set_article
    @article = Article.find(params[:article_id])
  end

  def comment_params
    params.require(:comment).permit(:commenter, :body, :status)
  end
end
