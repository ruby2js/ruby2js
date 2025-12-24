export class PostsIndexView extends ApplicationView {
  get title() {
    return "Blog Posts"
  };

  render({ posts }) {
    let _phlex_out = "";

    _phlex_out += `<div class="container">${_phlex_out += NavComponent.render({})}<header class="page-header"><h1>Blog Posts</h1><a href="/posts/new" onclick="return navigate(event, '/posts/new')" class="btn btn-primary">New Post</a></header>${posts.length === 0 ? _phlex_out += "<div class=\"empty-state\"><p>No posts yet. Be the first to write one!</p></div>" : _phlex_out += (() => { let _phlex_out = `<div class="posts-grid">`; for (let post of posts) {
      _phlex_out += PostCardComponent.render({post: post})
    } _phlex_out += `</div>`; return _phlex_out; })()}</div>`;

    return _phlex_out
  }
}
//# sourceMappingURL=posts_index_view.js.map
