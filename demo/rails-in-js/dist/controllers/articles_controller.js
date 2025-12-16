// Articles controller - handles article CRUD
class ArticlesController extends ApplicationController {
  #article;
  #articles;

  // GET /articles
  get index() {
    this.#articles = Article.all;
    set_instance_variable("articles", this.#articles);
    return render("index")
  };

  // GET /articles/:id
  get show() {
    set_instance_variable("article", this.#article);
    return render("show")
  };

  // GET /articles/new
  get new() {
    this.#article = new Article;
    set_instance_variable("article", this.#article);
    return render("new")
  };

  // POST /articles
  get create() {
    this.#article = new Article(this.#article_params);

    if (this.#article.save) {
      return redirect_to(this.#article)
    } else {
      set_instance_variable("article", this.#article);
      return render("new", {status: "unprocessable_entity"})
    }
  };

  // GET /articles/:id/edit
  get edit() {
    set_instance_variable("article", this.#article);
    return render("edit")
  };

  // PATCH/PUT /articles/:id
  get update() {
    if (this.#article.update(this.#article_params)) {
      return redirect_to(this.#article)
    } else {
      set_instance_variable("article", this.#article);
      return render("edit", {status: "unprocessable_entity"})
    }
  };

  // DELETE /articles/:id
  get destroy() {
    this.#article.destroy;
    return redirect_to("/articles")
  };

  get #set_article() {
    this.#article = Article.find(params.id);
    return this.#article
  };

  get #article_params() {
    return params.require("article").permit("title", "body")
  }
};

ArticlesController.before_action(
  "set_article",
  {only: ["show", "edit", "update", "destroy"]}
)