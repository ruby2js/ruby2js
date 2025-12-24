export class PostsNewView extends ApplicationView {
  get title() {
    return "New Post"
  };

  render({ post }) {
    let _phlex_out = "";
    _phlex_out += `<div class="container">${_phlex_out += NavComponent.render({})}<div class="form-container"><h1>New Post</h1>${_phlex_out += PostFormComponent.render({post: post, action: "posts.post", method: "post"})}<div class="form-footer"><a href="/posts" onclick="return navigate(event, '/posts')" class="back-link">Back to Posts</a></div></div></div>`;
    return _phlex_out
  }
}
//# sourceMappingURL=posts_new_view.js.map
