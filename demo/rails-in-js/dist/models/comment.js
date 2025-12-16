import ApplicationRecord from "./application_record.js";

// Comment model
// Note: Article is referenced at runtime, not imported to avoid circular dependency
export class Comment extends ApplicationRecord {
  #attributes;

  static get table_name() {
    return "comments"
  };

  // belongs_to :article
  get article() {
    return Article.find(this.#attributes.article_id)
  };

  get validate() {
    this.validates_presence_of("commenter");
    return this.validates_presence_of("body")
  };

  // Attribute accessors
  get commenter() {
    return this.#attributes.commenter
  };

  set commenter(value) {
    return this.#attributes.commenter = value
  };

  get body() {
    return this.#attributes.body
  };

  set body(value) {
    return this.#attributes.body = value
  };

  get article_id() {
    return this.#attributes.article_id
  };

  set article_id(value) {
    return this.#attributes.article_id = value
  };

  get status() {
    return this.#attributes.status
  };

  set status(value) {
    return this.#attributes.status = value
  };

  get created_at() {
    return this.#attributes.created_at
  }
}