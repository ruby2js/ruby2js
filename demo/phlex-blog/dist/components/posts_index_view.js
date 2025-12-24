export class PostsIndexView extends ApplicationView {
  #posts;

  constructor({ posts }) {
    this.#posts = posts
  };

  get title() {
    return "Blog Posts"
  };

  get view_template() {
    return div({class: "container"}, () => {
      render(new NavComponent);

      header({class: "page-header"}, () => {
        h1(() => "Blog Posts");

        a(
          {
            href: "/posts/new",
            onclick: "return navigate(event, '/posts/new')",
            class: "btn btn-primary"
          },

          () => "New Post"
        )
      });

      if (this.#posts.length === 0) {
        div(
          {class: "empty-state"},
          () => p(() => "No posts yet. Be the first to write one!")
        )
      } else {
        div({class: "posts-grid"}, () => {
          for (let post of this.#posts) {
            render(new PostCardComponent({post}))
          }
        })
      }
    })
  }
}
//# sourceMappingURL=posts_index_view.js.map
