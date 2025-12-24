export class PostsShowView extends ApplicationView {
  #post;

  constructor({ post }) {
    this.#post = post
  };

  get title() {
    return this.#post.title
  };

  get view_template() {
    return div({class: "container"}, () => {
      render(new NavComponent);

      article({class: "post-detail"}, () => {
        header({class: "post-header"}, () => {
          h1(() => this.#post.title);

          div({class: "post-meta"}, () => {
            span({class: "post-author"}, () => `By ${this.#post.author}`);

            span(
              {class: "post-date"},
              () => this.format_date(this.#post.created_at)
            )
          })
        });

        div({class: "post-body"}, () => p(() => this.#post.body));

        footer({class: "post-footer"}, () => {
          div({class: "post-actions"}, () => {
            a(
              {
                href: `/posts/${this.#post.id}/edit`,
                onclick: `return navigate(event, '/posts/${this.#post.id}/edit')`,
                class: "btn btn-secondary"
              },

              () => "Edit"
            );

            a(
              {
                href: "#",
                onclick: `if(confirm('Delete this post?')) { routes.post.delete(${this.#post.id}) } return false;`,
                class: "btn btn-destructive"
              },

              () => "Delete"
            )
          });

          a(
            {
              href: "/posts",
              onclick: "return navigate(event, '/posts')",
              class: "back-link"
            },

            () => "Back to Posts"
          )
        })
      })
    })
  }
}
//# sourceMappingURL=posts_show_view.js.map
