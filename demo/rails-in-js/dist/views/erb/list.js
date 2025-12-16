export function render({ articles }) {
  let _buf = "";
  _buf += `<h1>Articles</h1>\n\n`;

  for (let article of articles) {
    _buf += `  <div class="article">\n    <h2><a onclick="navigate('/articles/`;
    _buf += String(article.id);
    _buf += "')\">";
    _buf += String(article.title);
    _buf += `</a></h2>\n    <p>`;
    _buf += String((article.body ?? "").slice(0, 0 + 150));
    _buf += `...</p>\n    <p class="meta">Created: `;
    _buf += String(article.created_at);
    _buf += `</p>\n  </div>\n`
  };

  _buf += `\n<p><a onclick="navigate('/articles/new')">New Article</a></p>\n`;
  return _buf
}