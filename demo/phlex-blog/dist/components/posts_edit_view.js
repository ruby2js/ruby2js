export class PostsEditView extends ApplicationView {
  #post;

  constructor({ post }) {
    this.#post = post
  };

  get title() {
    return "Edit Post"
  };

  get view_template() {
    return div({class: "container"}, () => {
      render(new NavComponent);

      div({class: "form-container"}, () => {
        h1(() => "Edit Post");

        render(new PostFormComponent({
          post: this.#post,
          action: "post.patch",
          method: "patch"
        }));

        div({class: "form-footer"}, () => {
          a(
            {
              href: `/posts/${this.#post.id}`,
              onclick: `return navigate(event, '/posts/${this.#post.id}')`,
              class: "back-link"
            },

            () => "Cancel"
          );

          let whitespace;
          span(() => "|");
          whitespace;

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
//# sourceMappingURL=posts_edit_view.js.map
