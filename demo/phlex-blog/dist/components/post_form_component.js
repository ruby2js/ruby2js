export class PostFormComponent extends Phlex.HTML {
  render({ action, method, post }) {
    let _phlex_out = "";

    if (post.errors && post.errors.length > 0) {
      _phlex_out += (() => { let _phlex_out = `<div class="form-errors">`; _phlex_out += (() => { let _phlex_out = `<ul>`; for (let error of post.errors) {
        _phlex_out += `<li>${String(error)}</li>`
      } _phlex_out += `</ul>`; return _phlex_out; })(); _phlex_out += `</div>`; return _phlex_out; })()
    };

    _phlex_out += `<form class="post-form" onsubmit="${`return routes.${action}(event)`}"><div class="form-group"><label for="title">Title</label><input type="text" id="title" name="title" value="${post.title ?? ""}" required class="input"></div><div class="form-group"><label for="author">Author</label><input type="text" id="author" name="author" value="${post.author ?? ""}" required class="input"></div><div class="form-group"><label for="body">Content</label><textarea id="body" name="body" required class="input textarea" rows="${8}">${post.body ?? ""}</textarea></div><div class="form-actions"><button type="submit" class="btn btn-primary">${method === "post" ? "Create Post" : "Update Post"}</button></div></form>`;
    return _phlex_out
  }
}
//# sourceMappingURL=post_form_component.js.map
