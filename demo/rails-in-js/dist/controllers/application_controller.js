// Base controller class
class ApplicationController {
  #params = {};
  #instance_variables = {};
  #before_actions;
  #hash;
  #params_obj;
  #request;
  #response;

  get params() {
    return this.#params
  };

  set params(params) {
    this.#params = params
  };

  get request() {
    return this.#request
  };

  set request(request) {
    this.#request = request
  };

  get response() {
    return this.#response
  };

  set response(response) {
    this.#response = response
  };

  // Instance variable handling for views
  set_instance_variable(name, value) {
    return this.#instance_variables[name] = value
  };

  get get_instance_variables() {
    return this.#instance_variables
  };

  // Render a view template
  render(template, options={}) {
    let status = options.status ?? 200;
    let locals = this.#instance_variables.dup();

    if (typeof template === "symbol") {
      template = `${this.controller_name}/${template}`
    };

    let html = Views.render(template, locals);
    return {status, body: html, type: "html"}
  };

  // template can be :new, :edit, etc. or "articles/show"
  // Redirect to a path
  redirect_to(target) {
    let path = typeof target === "string" ? target : "id" in target ? `/${target.constructor.name.toLowerCase()}s/${target.id}` : target.toString();
    return {status: 302, redirect: path}
  };

  // redirect_to @article
  // Helper to get controller name from class
  get controller_name() {
    return this.constructor.name.replaceAll("Controller", "").toLowerCase()
  };

  get params() {
    return this.#params_obj ??= new Parameters(this.#params)
  };

  // before_action support
  static get before_actions() {
    return this.#before_actions ??= []
  };

  static before_action(method_name, options={}) {
    return this.before_actions << {method: method_name, options}
  };

  static run_before_actions(controller, action) {
    for (let ba of this.before_actions) {
      let only = ba.options.only;
      let except = ba.options.except;
      let should_run = true;
      if (only) should_run = only.includes(action);
      if (except) should_run = !except.includes(action);
      if (should_run) controller[ba.method]()
    }
  }
};

// Strong parameters helpers
ApplicationController.Parameters = class {
  #hash;

  constructor(hash) {
    this.#hash = hash ?? {}
  };

  require(key) {
    let value = this.#hash[key.toString()] ?? this.#hash[key];
    if (!value) throw `param is missing or the value is empty: ${key}`;
    return new Parameters(value)
  };

  permit(...keys) {
    let result = {};

    for (let key of keys) {
      let key_s = key.toString();
      if (key_s in this.#hash) result[key_s] = this.#hash[key_s];
      if (key in this.#hash) result[key_s] = this.#hash[key]
    };

    return result
  };

  [](key) {
    return this.#hash[key.toString()] ?? this.#hash[key]
  };

  get to_h() {
    return this.#hash
  }
}