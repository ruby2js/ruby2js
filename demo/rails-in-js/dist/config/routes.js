export const Routes = (() => {
  function routes() {
    return [
      {path: "/", controller: "ArticlesController", action: "index!"},

      {
        path: "/articles",
        controller: "ArticlesController",
        action: "index!",
        method: "GET"
      },

      {
        path: "/articles/new",
        controller: "ArticlesController",
        action: "$new",
        method: "GET"
      },

      {
        path: "/articles",
        controller: "ArticlesController",
        action: "create",
        method: "POST"
      },

      {
        path: "/articles/:id",
        controller: "ArticlesController",
        action: "show",
        method: "GET"
      },

      {
        path: "/articles/:id/edit",
        controller: "ArticlesController",
        action: "edit",
        method: "GET"
      },

      {
        path: "/articles/:id",
        controller: "ArticlesController",
        action: "update",
        method: "PATCH"
      },

      {
        path: "/articles/:id",
        controller: "ArticlesController",
        action: "destroy",
        method: "DELETE"
      },

      {
        path: "/articles/:article_id/comments",
        controller: "CommentsController",
        action: "create",
        method: "POST"
      },

      {
        path: "/articles/:article_id/comments/:id",
        controller: "CommentsController",
        action: "destroy",
        method: "DELETE"
      }
    ]
  };

  function root_path() {
    return "/"
  };

  function articles_path() {
    return "/articles"
  };

  function new_article_path() {
    return "/articles/new"
  };

  function article_path(article) {
    return `/articles/${extract_id(article)}`
  };

  function edit_article_path(article) {
    return `/articles/${extract_id(article)}/edit`
  };

  function comments_path(article) {
    return `/articles/${extract_id(article)}/comments`
  };

  function comment_path(article, comment) {
    return `/articles/${extract_id(article)}/comments/${extract_id(comment)}`
  };

  function extract_id(obj) {
    return obj?.id() || obj
  };

  return {
    routes,
    root_path,
    articles_path,
    new_article_path,
    article_path,
    edit_article_path,
    comments_path,
    comment_path,
    extract_id
  }
})()