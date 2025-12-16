// Routes configuration
// Defines URL patterns and maps them to controllers/actions
const Routes = {
  routes: [],

  root(controller_action) {
    let [controller, action] = controller_action.split("#");

    return Routes.routes << {
      method: "GET",
      path: /^\/$/m,
      controller,
      action
    }
  },

  resources(name, options={}, block) {
    Routes.routes.push({
      method: "GET",
      path: new RegExp(`^/${name}$`),
      controller: name,
      action: "index"
    });

    Routes.routes.push({
      method: "GET",
      path: new RegExp(`^/${name}/new$`),
      controller: name,
      action: "new"
    });

    Routes.routes.push({
      method: "GET",
      path: new RegExp(`^/${name}/(\\d+)$`),
      controller: name,
      action: "show"
    });

    Routes.routes.push({
      method: "GET",
      path: new RegExp(`^/${name}/(\\d+)/edit$`),
      controller: name,
      action: "edit"
    });

    Routes.routes.push({
      method: "POST",
      path: new RegExp(`^/${name}$`),
      controller: name,
      action: "create"
    });

    Routes.routes.push({
      method: "PATCH",
      path: new RegExp(`^/${name}/(\\d+)$`),
      controller: name,
      action: "update"
    });

    Routes.routes.push({
      method: "PUT",
      path: new RegExp(`^/${name}/(\\d+)$`),
      controller: name,
      action: "update"
    });

    Routes.routes.push({
      method: "DELETE",
      path: new RegExp(`^/${name}/(\\d+)$`),
      controller: name,
      action: "destroy"
    });

    if (block) {
      this.#parent_resource = name;
      block();
      this.#parent_resource = null;
      return this.#parent_resource
    }
  },

  // Standard RESTful routes
  // Handle nested resources via block
  // For nested resources
  nested_resources(name, options={}) {
    let parent = this.#parent_resource;

    let only = options.only ?? [
      "index",
      "show",
      "new",
      "create",
      "edit",
      "update",
      "destroy"
    ];

    if (only.includes("create")) {
      Routes.routes.push({
        method: "POST",
        path: new RegExp(`^/${parent}/(\\d+)/${name}$`),
        controller: name,
        action: "create",
        parent
      })
    };

    if (only.includes("destroy")) {
      return Routes.routes << {
        method: "DELETE",
        path: new RegExp(`^/${parent}/(\\d+)/${name}/(\\d+)$`),
        controller: name,
        action: "destroy",
        parent
      }
    }
  },

  match(method, path) {
    for (let route of Routes.routes) {
      if (route.method != method) continue;
      let match_result = path.match(route.path);

      if (match_result) {
        return {
          controller: route.controller,
          action: route.action,
          params: extract_params(match_result, route)
        }
      }
    };

    return null
  },

  extract_params(match_result, route) {
    let params = {};

    if (route.parent) {
      if (match_result[1]) {
        params[`${route.parent.toString().chomp("s")}_id`] = parseInt(match_result[1])
      };

      if (match_result[2]) params.id = parseInt(match_result[2])
    } else if (match_result[1]) {
      params.id = parseInt(match_result[1])
    };

    return params
  }
};

// Nested resource: first capture is parent_id, second is id
// Regular resource: first capture is id
// Define application routes
Routes.root("articles#index");

Routes.resources(
  "articles",
  () => Routes.nested_resources("comments", {only: ["create", "destroy"]})
)