export const Routes = (() => {
  this.#routes = [];
  this.#parent_resource = null;

  function routes() {
    return this.#routes
  };

  function root(controller_action) {
    let [controller, action] = controller_action.split("#");

    return this.#routes.push({
      method: "GET",
      path: /^\/$/m,
      controller,
      action
    })
  };

  function resources(name, options={}, block) {
    this.#routes.push({
      method: "GET",
      path: new RegExp(`^/${name}$`),
      controller: name,
      action: "list"
    });

    this.#routes.push({
      method: "GET",
      path: new RegExp(`^/${name}/new$`),
      controller: name,
      action: "new_form"
    });

    this.#routes.push({
      method: "GET",
      path: new RegExp(`^/${name}/(\\d+)$`),
      controller: name,
      action: "show"
    });

    this.#routes.push({
      method: "GET",
      path: new RegExp(`^/${name}/(\\d+)/edit$`),
      controller: name,
      action: "edit"
    });

    this.#routes.push({
      method: "POST",
      path: new RegExp(`^/${name}$`),
      controller: name,
      action: "create"
    });

    this.#routes.push({
      method: "PATCH",
      path: new RegExp(`^/${name}/(\\d+)$`),
      controller: name,
      action: "update"
    });

    this.#routes.push({
      method: "PUT",
      path: new RegExp(`^/${name}/(\\d+)$`),
      controller: name,
      action: "update"
    });

    this.#routes.push({
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
  };

  function nested_resources(name, options={}) {
    let parent = this.#parent_resource;

    let only = options.only ?? [
      "list",
      "show",
      "new_form",
      "create",
      "edit",
      "update",
      "destroy"
    ];

    if (only.includes("create")) {
      this.#routes.push({
        method: "POST",
        path: new RegExp(`^/${parent}/(\\d+)/${name}$`),
        controller: name,
        action: "create",
        parent
      })
    };

    if (only.includes("destroy")) {
      return this.#routes.push({
        method: "DELETE",
        path: new RegExp(`^/${parent}/(\\d+)/${name}/(\\d+)$`),
        controller: name,
        action: "destroy",
        parent
      })
    }
  };

  function match(method, path) {
    for (let route of this.#routes) {
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
  };

  function extract_params(match_result, route) {
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
  };

  return {
    routes,
    root,
    resources,
    nested_resources,
    match,
    extract_params
  }
})();

// Routes configuration
// Defines URL patterns and maps them to controllers/actions
// Standard RESTful routes
// Handle nested resources via block
// For nested resources
// Nested resource: first capture is parent_id, second is id
// Regular resource: first capture is id
// Define application routes
Routes.root("articles#list");

Routes.resources(
  "articles",
  () => Routes.nested_resources("comments", {only: ["create", "destroy"]})
)