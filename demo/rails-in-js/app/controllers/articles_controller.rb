# Articles controller - handles article CRUD
class ArticlesController < ApplicationController
  before_action :set_article, only: [:show, :edit, :update, :destroy]

  # GET /articles
  def index
    @articles = Article.all
    set_instance_variable('articles', @articles)
    render :index
  end

  # GET /articles/:id
  def show
    set_instance_variable('article', @article)
    render :show
  end

  # GET /articles/new
  def new
    @article = Article.new
    set_instance_variable('article', @article)
    render :new
  end

  # POST /articles
  def create
    @article = Article.new(article_params)
    if @article.save
      redirect_to @article
    else
      set_instance_variable('article', @article)
      render :new, status: :unprocessable_entity
    end
  end

  # GET /articles/:id/edit
  def edit
    set_instance_variable('article', @article)
    render :edit
  end

  # PATCH/PUT /articles/:id
  def update
    if @article.update(article_params)
      redirect_to @article
    else
      set_instance_variable('article', @article)
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /articles/:id
  def destroy
    @article.destroy
    redirect_to '/articles'
  end

  private

  def set_article
    @article = Article.find(params[:id])
  end

  def article_params
    params.require(:article).permit(:title, :body)
  end
end
