import { Router, Application, formData, handleFormResult } from "../lib/rails.js";
import { Schema } from "./schema.js";
import { Seeds } from "../db/seeds.js";
import { PostsController } from "../controllers/posts_controller.js";
import { extract_id, root_path, posts_path, new_post_path, post_path, edit_post_path } from "./paths.js";
Router.root("/posts");
Router.resources("posts", PostsController);

const routes = {
  posts: {
    get() {
      return PostsController.index()
    },

    post: async (event) => {
      let result = await PostsController.create(formData(event));
      handleFormResult(result);
      return false
    }
  },

  post: {
    get(id) {
      return PostsController.show(id)
    },

    put: async (event, id) => {
      let result = await PostsController.update(id, formData(event));
      handleFormResult(result);
      return false
    },

    patch: async (event, id) => {
      let result = await PostsController.update(id, formData(event));
      handleFormResult(result);
      return false
    },

    delete: async (id) => {
      let result = await PostsController.destroy(id);
      handleFormResult(result);
      return false
    }
  }
};

Application.configure({schema: Schema, seeds: Seeds});
export { Application, routes, root_path, posts_path, new_post_path, post_path, edit_post_path }
// Routes configuration - idiomatic Rails