// Path helpers for URL generation
// Mimics Rails route helpers
export const PathHelpers = (() => {
  function articles_path() {
    return "/articles"
  };

  function article_path(article) {
    let id = extract_id(article);
    return `/articles/${id}`
  };

  function new_article_path() {
    return "/articles/new"
  };

  function edit_article_path(article) {
    let id = extract_id(article);
    return `/articles/${id}/edit`
  };

  // Comments paths (nested under articles)
  function article_comments_path(article) {
    let id = extract_id(article);
    return `/articles/${id}/comments`
  };

  function article_comment_path(article, comment) {
    let article_id = extract_id(article);
    let comment_id = extract_id(comment);
    return `/articles/${article_id}/comments/${comment_id}`
  };

  function extract_id(obj) {
    // If obj has an id property, use it; otherwise obj is the id
    return (obj?.id) || obj
  };

  // Root path
  function root_path() {
    return "/"
  };

  return {
    articles_path,
    article_path,
    new_article_path,
    edit_article_path,
    article_comments_path,
    article_comment_path,
    extract_id,
    root_path
  }
})()