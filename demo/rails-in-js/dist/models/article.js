// Article model - idiomatic Rails
import { ApplicationRecord } from "./application_record.js";

export class Article extends ApplicationRecord {
  static table_name = "articles";

  get comments() {
    return Comment.where({article_id: this._id})
  };

  destroy() {
    this.comments.forEach(record => record.destroy());
    return super.destroy()
  };

  validate() {
    this.validates_presence_of("title");
    this.validates_presence_of("body");
    return this.validates_length_of("body", {minimum: 10})
  }
}