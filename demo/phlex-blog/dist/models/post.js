import { ApplicationRecord } from "./application_record.js";

export class Post extends ApplicationRecord {
  static table_name = "posts";

  validate() {
    this.validates_presence_of("title");
    this.validates_presence_of("body");
    this.validates_length_of("body", {minimum: 10});
    return this.validates_presence_of("author")
  }
}
//# sourceMappingURL=post.js.map
