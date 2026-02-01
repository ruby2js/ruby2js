import { Router, Application, createContext, formData, handleFormResult } from 'ruby2js-rails/targets/node/rails.js';
import { migrations } from "../db/migrate/index.js";
import { Seeds } from "../db/seeds.js";
import { layout } from "../app/views/layouts/application.js";
import { ClipsController } from "../app/controllers/clips_controller.js";
import { createPathHelper } from 'ruby2js-rails/path_helper.mjs';

function extract_id(obj) {
  return obj && obj.id || obj
};

function root_path() {
  return createPathHelper("/")
};

function clips_path() {
  return createPathHelper("/clips")
};

function clip_path(clip) {
  return createPathHelper(`/clips/${extract_id(clip)}`)
};

Router.root("/", ClipsController, "index");

Router.resources(
  "clips",
  ClipsController,
  {only: ["index", "show", "create", "update", "destroy"]}
);

const routes = {
  clips: {
    get() {
      return ClipsController.index(createContext())
    },

    post: async (event) => {
      let params = formData(event);
      let context = createContext(params);
      let result = await ClipsController.create(context, params);
      handleFormResult(context, result);
      return false
    }
  },

  clip: {
    get(id) {
      return ClipsController.show(createContext(), id)
    },

    put: async (event, id) => {
      let params = formData(event);
      let context = createContext(params);
      let result = await ClipsController.update(context, id, params);
      handleFormResult(context, result);
      return false
    },

    patch: async (event, id) => {
      let params = formData(event);
      let context = createContext(params);
      let result = await ClipsController.update(context, id, params);
      handleFormResult(context, result);
      return false
    },

    delete: async (id) => {
      let context = createContext();
      let result = await ClipsController.destroy(context, id);
      handleFormResult(context, result);
      return false
    }
  }
};

Application.configure({
  migrations: migrations,
  seeds: Seeds,
  layout: layout
});

export { Application, routes, root_path, clips_path, clip_path }