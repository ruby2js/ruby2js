export class PostsNewView extends ApplicationView {
  #post;

  constructor({ post }) {
    this.#post = post
  };

  get title() {
    return "New Post"
  };

  get view_template() {
    return div({class: "container"}, () => {
      render(new NavComponent);

      div({class: "form-container"}, () => {
        h1(() => "New Post");

        render(new PostFormComponent({
          post: this.#post,
          action: "posts.post",
          method: "post"
        }));

        div({class: "form-footer"}, () => (
          a(
            {
              href: "/posts",
              onclick: "return navigate(event, '/posts')",
              class: "back-link"
            },

            () => "Back to Posts"
          )
        ))
      })
    })
  }
}
//# sourceMappingURL=posts_new_view.js.map
