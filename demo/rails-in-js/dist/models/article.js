import ApplicationRecord from "./application_record.js";
import Comment from "./comment.js";

// Article model
export class Article extends ApplicationRecord {
  #attributes;
  #id;

  static get table_name() {
    return "articles"
  };

  // has_many :comments, dependent: :destroy
  get comments() {
    return Comment.where({article_id: this.#id})
  };

  get validate() {
    this.validates_presence_of("title");
    this.validates_presence_of("body");
    return this.validates_length_of("body", {minimum: 10})
  };

  // Attribute accessors
  get title() {
    return this.#attributes.title
  };

  set title(value) {
    return this.#attributes.title = value
  };

  get body() {
    return this.#attributes.body
  };

  set body(value) {
    return this.#attributes.body = value
  };

  get created_at() {
    return this.#attributes.created_at
  };

  get updated_at() {
    return this.#attributes.updated_at
  };

  // Destroy associated comments
  get destroy() {
    for (let c of this.comments) {
      c.destroy
    };

    return super.destroy
  }
}