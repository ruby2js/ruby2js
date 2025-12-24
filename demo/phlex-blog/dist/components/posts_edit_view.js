export class PostsEditView extends ApplicationView {
  get title() {
    return "Edit Post"
  };

  render({ post }) {
    let _phlex_out = "";
    _phlex_out += `<div class="container">${_phlex_out += NavComponent.render({})}<div class="form-container"><h1>Edit Post</h1>${_phlex_out += PostFormComponent.render({post: post, action: "post.patch", method: "patch"})}<div class="form-footer"><a href="${`/posts/${post.id}`}" onclick="${`return navigate(event, '/posts/${post.id}')`}" class="back-link">Cancel</a>${_phlex_out += " "}<span>|</span>${_phlex_out += " "}<a href="/posts" onclick="return navigate(event, '/posts')" class="back-link">Back to Posts</a></div></div></div>`;
    return _phlex_out
  }
}
//# sourceMappingURL=posts_edit_view.js.map
