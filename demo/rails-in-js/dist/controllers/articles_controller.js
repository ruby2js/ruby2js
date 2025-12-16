import { Article } from "../models/article.js";
import { ArticleViews } from "../views/articles.js";

// Articles controller - SPA-friendly version
// Uses direct model/view calls instead of Rails conventions
export const ArticlesController = (() => {
  function list() {
    let articles = Article.all;
    return ArticleViews.list({articles})
  };

  function show(id) {
    let article = Article.find(id);
    return ArticleViews.show({article})
  };

  function new_form() {
    let article = {title: "", body: "", errors: []};
    return ArticleViews.new_article({article})
  };

  function edit(id) {
    let article = Article.find(id);
    return ArticleViews.edit({article})
  };

  function create(title, body) {
    let article = Article.create({title, body});

    return article.id ? {success: true, id: article.id} : {
      success: false,
      html: ArticleViews.new_article({article})
    }
  };

  function update(id, title, body) {
    let article = Article.find(id);
    article.title = title;
    article.body = body;

    return article.save ? {success: true, id: article.id} : {
      success: false,
      html: ArticleViews.edit({article})
    }
  };

  function destroy(id) {
    let article = Article.find(id);
    article.destroy;
    return {success: true}
  };

  return {list, show, new_form, edit, create, update, destroy}
})()