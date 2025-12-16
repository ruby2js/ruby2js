export function render({ article }) {
  let _buf = "";
  _buf += `<h1>New Article</h1>\n\n`;

  if (article.errors && article.errors.length > 0) {
    _buf += `  <div class="errors">\n    <ul>\n`;

    for (let error of article.errors) {
      _buf += "        <li>";
      _buf += String(error);
      _buf += `</li>\n`
    };

    _buf += `    </ul>\n  </div>\n`
  };

  _buf += `
<form onsubmit="return createArticle(event)">
  <p>
    <label>Title:</label>
    <input type="text" id="title" value="`;
  _buf += String(article.title ?? "");
  _buf += `" required>
  </p>
  <p>
    <label>Body:</label>
    <textarea id="body" required>`;
  _buf += String(article.body ?? "");
  _buf += `</textarea>
  </p>
  <button type="submit">Create Article</button>
</form>

<p><a onclick="navigate('/articles')">Back to Articles</a></p>
`;
  return _buf
}