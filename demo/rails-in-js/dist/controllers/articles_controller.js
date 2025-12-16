// Articles controller - idiomatic Rails
import { Article } from "../models/article.js";
import { ArticleViews } from "../views/articles.js";

export const ArticlesController = (() => {
  function index() {
    let articles = Article.all;
    return ArticleViews.index({articles})
  };

  function show(id) {
    let article = Article.find(id);
    return ArticleViews.show({article})
  };

  function $new() {
    let article = new Article;
    return ArticleViews.$new({article})
  };

  function create(params) {
    let article = new Article(params);
    return article.save ? {redirect: `/articles/${article.id}`} : {render: "new_article"}
  };

  function edit(id) {
    let article = Article.find(id);
    return ArticleViews.edit({article})
  };

  function update(id, params) {
    let article = Article.find(id);
    return article.update(params) ? {redirect: `/articles/${article.id}`} : {render: "edit"}
  };

  function destroy(id) {
    let article = Article.find(id);
    article.destroy;
    return {redirect: "/articles"}
  };

  return {index, show, $new, create, edit, update, destroy}
})()