export class PostCardComponent extends ApplicationView {
  render({ post }) {
    let _phlex_out = "";

    _phlex_out += `<article class="post-card"><header class="post-card-header"><h2 class="post-card-title"><a href="${`/posts/${post.id}`}" onclick="${`return navigate(event, '/posts/${post.id}')`}">${String(post.title)}</a></h2><div class="post-card-meta"><span class="post-author">${String(post.author)}</span><span class="post-date">${String(this.time_ago(post.created_at))}</span></div></header><div class="post-card-body"><p>${String(this.truncate(
      post.body,
      {length: 150}
    ))}</p></div><footer class="post-card-footer"><a href="${`/posts/${post.id}`}" onclick="${`return navigate(event, '/posts/${post.id}')`}" class="read-more">Read more</a></footer></article>`;

    return _phlex_out
  }
}
//# sourceMappingURL=post_card_component.js.map
