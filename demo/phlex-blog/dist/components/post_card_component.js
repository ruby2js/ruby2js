export class PostCardComponent extends ApplicationView {
  #post;

  constructor({ post }) {
    this.#post = post
  };

  get view_template() {
    return article({class: "post-card"}, () => {
      header({class: "post-card-header"}, () => {
        h2({class: "post-card-title"}, () => (
          a(
            {
              href: `/posts/${this.#post.id}`,
              onclick: `return navigate(event, '/posts/${this.#post.id}')`
            },

            () => this.#post.title
          )
        ));

        div({class: "post-card-meta"}, () => {
          span({class: "post-author"}, () => this.#post.author);

          span(
            {class: "post-date"},
            () => this.time_ago(this.#post.created_at)
          )
        })
      });

      div(
        {class: "post-card-body"},
        () => p(() => this.truncate(this.#post.body, {length: 150}))
      );

      footer({class: "post-card-footer"}, () => (
        a(
          {
            href: `/posts/${this.#post.id}`,
            onclick: `return navigate(event, '/posts/${this.#post.id}')`,
            class: "read-more"
          },

          () => "Read more"
        )
      ))
    })
  }
}
//# sourceMappingURL=post_card_component.js.map
