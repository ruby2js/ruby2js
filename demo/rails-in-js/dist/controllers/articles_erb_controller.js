import { Article } from "../models/article.js";
import { ArticleErbViews } from "../views/article_erb_views.js";

// Articles controller using ERB-transpiled views
// Identical to articles_controller.rb but uses ArticleErbViews
export const ArticlesErbController = (() => {
  function list() {
    let articles = Article.all;
    return ArticleErbViews.list({articles})
  };

  function show(id) {
    let article = Article.find(id);
    return ArticleErbViews.show({article})
  };

  function new_form() {
    let article = {title: "", body: "", errors: []};
    return ArticleErbViews.new_article({article})
  };

  function edit(id) {
    let article = Article.find(id);
    return ArticleErbViews.edit({article})
  };

  function create(title, body) {
    let article = Article.create({title, body});

    return article.id ? {success: true, id: article.id} : {
      success: false,
      html: ArticleErbViews.new_article({article})
    }
  };

  function update(id, title, body) {
    let article = Article.find(id);
    article.title = title;
    article.body = body;

    return article.save ? {success: true, id: article.id} : {
      success: false,
      html: ArticleErbViews.edit({article})
    }
  };

  function destroy(id) {
    let article = Article.find(id);
    article.destroy;
    return {success: true}
  };

  return {list, show, new_form, edit, create, update, destroy}
})()