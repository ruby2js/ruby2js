export function render({ article }) {
  let _buf = "";
  _buf += "<h1>";
  _buf += String(article.title);
  _buf += `</h1>\n\n<p>`;
  _buf += String(article.body);
  _buf += `</p>\n\n<p class="meta">\n  Created: `;
  _buf += String(article.created_at);
  _buf += `<br>\n  Updated: `;
  _buf += String(article.updated_at);
  _buf += `\n`;
  _buf += `</p>\n\n<p>\n  <a onclick="navigate('/articles/`;
  _buf += String(article.id);
  _buf += `/edit')">Edit</a> |\n  <a onclick="navigate('/articles')">Back to Articles</a> |\n  <a onclick="deleteArticle(`;
  _buf += String(article.id);
  _buf += `)" style="color: red;">Delete</a>
</p>

<hr>

<h2>Comments</h2>

`;

  for (let comment of article.comments()) {
    _buf += `  <div class="comment">\n    <p><strong>`;
    _buf += String(comment.commenter);
    _buf += `</strong> says:</p>\n    <p>`;
    _buf += String(comment.body);
    _buf += `</p>\n    <button class="danger" onclick="deleteComment(`;
    _buf += String(article.id);
    _buf += ", ";
    _buf += String(comment.id);
    _buf += `)">Delete</button>\n  </div>\n`
  };

  _buf += `\n<h3>Add a Comment</h3>\n\n<form onsubmit="return createComment(event, `;
  _buf += String(article.id);
  _buf += `)">
  <p>
    <label>Your Name:</label>
    <input type="text" id="commenter" required>
  </p>
  <p>
    <label>Comment:</label>
    <textarea id="comment_body" required></textarea>
  </p>
  <button type="submit">Add Comment</button>
</form>
`;
  return _buf
}