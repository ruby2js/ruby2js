// Comment model - idiomatic Rails
import { ApplicationRecord } from "./application_record.js";

export class Comment extends ApplicationRecord {
  static table_name = "comments";

  article() {
    return Article.find(this._attributes["article_id".toString()])
  };

  validate() {
    this.validates_presence_of("commenter");
    return this.validates_presence_of("body")
  }
}