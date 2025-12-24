export class PostsShowView extends ApplicationView {
  #post;

  get title() {
    return this.#post.title
  };

  render({ post }) {
    let _phlex_out = "";
    _phlex_out += `<div class="container">${_phlex_out += NavComponent.render({})}<article class="post-detail"><header class="post-header"><h1>${String(post.title)}</h1><div class="post-meta"><span class="post-author">${String(`By ${post.author}`)}</span><span class="post-date">${String(this.format_date(post.created_at))}</span></div></header><div class="post-body"><p>${String(post.body)}</p></div><footer class="post-footer"><div class="post-actions"><a href="${`/posts/${post.id}/edit`}" onclick="${`return navigate(event, '/posts/${post.id}/edit')`}" class="btn btn-secondary">Edit</a><a href="#" onclick="${`if(confirm('Delete this post?')) { routes.post.delete(${post.id}) } return false;`}" class="btn btn-destructive">Delete</a></div><a href="/posts" onclick="return navigate(event, '/posts')" class="back-link">Back to Posts</a></footer></article></div>`;
    return _phlex_out
  }
}
//# sourceMappingURL=posts_show_view.js.map
