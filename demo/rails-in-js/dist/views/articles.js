// Views for Articles - will be transpiled to JavaScript
// These are Ruby functions that return HTML strings
export const ArticleViews = (() => {
  function escape_html(str) {
    if (str == null) return "";

    return String(str).replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(
      ">",
      "&gt;"
    ).replaceAll("\"", "&quot;")
  };

  function list(locals) {
    let articles = locals.articles;
    let html = "<h1>Articles</h1>";

    for (let article of articles) {
      html += `
        <div class="article">
          <h2><a onclick="navigate('/articles/${article.id}')">${escape_html(article.title)}</a></h2>
          <p>${escape_html((article.body ?? "").slice(
        0,
        0 + 150
      ))}...</p>
          <p class="meta">Created: ${article.created_at}</p>
        </div>`
    };

    html += "<p><a onclick=\"navigate('/articles/new')\">New Article</a></p>";
    return html
  };

  function show(locals) {
    let article = locals.article;
    let html = `
      <h1>${escape_html(article.title)}</h1>
      <p>${escape_html(article.body)}</p>
      <p class="meta">Created: ${article.created_at}<br>Updated: ${article.updated_at}</p>
      <p>
        <a onclick="navigate('/articles/${article.id}/edit')">Edit</a> |
        <a onclick="navigate('/articles')">Back to Articles</a> |
        <a onclick="deleteArticle(${article.id})" style="color: red;">Delete</a>
      </p>
      <hr>
      <h2>Comments</h2>`;
    let comments = article.comments;

    for (let comment of comments) {
      html += `
        <div class="comment">
          <p><strong>${escape_html(comment.commenter)}</strong> says:</p>
          <p>${escape_html(comment.body)}</p>
          <button class="danger" onclick="deleteComment(${article.id}, ${comment.id})">Delete</button>
        </div>`
    };

    html += `
      <h3>Add a Comment</h3>
      <form onsubmit="return createComment(event, ${article.id})">
        <p><label>Your Name:</label><input type="text" id="commenter" required></p>
        <p><label>Comment:</label><textarea id="comment_body" required></textarea></p>
        <button type="submit">Add Comment</button>
      </form>`;
    return html
  };

  function new_article(locals) {
    let article = locals.article ?? {title: "", body: "", errors: []};
    let html = "<h1>New Article</h1>";

    if (article.errors && article.errors.length > 0) {
      html += "<div class=\"errors\"><ul>";

      for (let error of article.errors) {
        html += `<li>${escape_html(error)}</li>`
      };

      html += "</ul></div>"
    };

    html += `
      <form onsubmit="return createArticle(event)">
        <p><label>Title:</label><input type="text" id="title" value="${escape_html(article.title ?? "")}" required></p>
        <p><label>Body:</label><textarea id="body" required>${escape_html(article.body ?? "")}</textarea></p>
        <button type="submit">Create Article</button>
      </form>
      <p><a onclick="navigate('/articles')">Back to Articles</a></p>`;
    return html
  };

  function edit(locals) {
    let article = locals.article;
    let html = "<h1>Edit Article</h1>";

    if (article.errors && article.errors.length > 0) {
      html += "<div class=\"errors\"><ul>";

      for (let error of article.errors) {
        html += `<li>${escape_html(error)}</li>`
      };

      html += "</ul></div>"
    };

    html += `
      <form onsubmit="return updateArticle(event, ${article.id})">
        <p><label>Title:</label><input type="text" id="title" value="${escape_html(article.title)}" required></p>
        <p><label>Body:</label><textarea id="body" required>${escape_html(article.body)}</textarea></p>
        <button type="submit">Update Article</button>
      </form>
      <p><a onclick="navigate('/articles/${article.id}')">Cancel</a> | <a onclick="navigate('/articles')">Back to Articles</a></p>`;
    return html
  };

  return {escape_html, list, show, new_article, edit}
})()