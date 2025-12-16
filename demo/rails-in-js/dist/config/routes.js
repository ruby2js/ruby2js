import { Router, Application, setupFormHandlers } from "../lib/rails.js";
import { Schema } from "./schema.js";
import { Seeds } from "../db/seeds.js";
import { ArticlesController } from "../controllers/articles_controller.js";
import { CommentsController } from "../controllers/comments_controller.js";
Router.root("/articles");

Router.resources("articles", ArticlesController, {nested: [{
  name: "comments",
  controller: CommentsController,
  only: ["create", "destroy"]
}]});

setupFormHandlers([
  {
    resource: "articles",
    confirmDelete: "Are you sure you want to delete this article?"
  },

  {
    resource: "comments",
    parent: "articles",
    confirmDelete: "Delete this comment?"
  }
]);

Application.configure({schema: Schema, seeds: Seeds});
export { Application }
//# sourceMappingURL=routes.js.map