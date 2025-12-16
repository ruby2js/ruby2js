Object.defineProperty(
  Array.prototype,
  "first",
  {get() {return this[0]}, configurable: true}
);

Object.defineProperty(
  Object.prototype,
  "to_a",
  {get() {return Object.entries(this)}, configurable: true}
);

Object.defineProperty(Array.prototype, "compact", {
  get() {
    return this.filter(x => x !== null && x !== undefined)
  },

  configurable: true
});

import { Parser, SEXP, s, S, ast_node, include, Filter, DEFAULTS, excluded, included, _options, filterContext, nodesEqual, registerFilter, scanRegexpGroups, Ruby2JS } from "../ruby2js.js";

class Erb extends Filter.Processor {
  // Track instance variables found during AST traversal
  constructor(...args) {
    this._erb_ivars = new Set;
    this._erb_bufvar = null;
    this._erb_block_var = null;

    // Track current block variable (e.g., 'f' in form_for)
    this._erb_model_name = null;

    // Track model name for form_for (e.g., 'user')
    super(...args)
  };

  // Main entry point - detect ERB/HERB output patterns and transform
  on_begin(node) {
    let args;

    // Unknown method - pass through
    // Check if this is the final expression (return value)
    // For now just return the variable as-is, the function will implicitly return it
    // Check if this looks like ERB/HERB output:
    // - First statement assigns to _erbout or _buf
    // - Last statement returns the buffer
    let children = node.children;
    if (children.length < 2) return super.on_begin(node);
    let first = children.first;

    // Detect buffer variable assignment
    let bufvar = null;

    if (first.type === "lvasgn") {
      let name = first.children.first;
      if (["_erbout", "_buf"].includes(name)) bufvar = name
    };

    if (!bufvar) return super.on_begin(node);
    this._erb_bufvar = bufvar;

    // Collect all instance variables used in the template
    this._erb_ivars = new Set;
    this._collect_ivars(node);

    // Transform the body, converting ivars to property access on 'data' param
    let transformed_children = children.map(child => this.process(child));

    // Build the function body with autoreturn for the last expression
    let body = s("autoreturn", ...transformed_children);

    // Create parameter for the function - destructure ivars from object
    if (this._erb_ivars.length === 0) {
      args = s("args")
    } else {
      // Create destructuring pattern: { title, content }
      let kwargs = this._erb_ivars.to_a.sort().map((ivar) => {
        let prop_name = (ivar ?? "").toString().slice(1);

        // @title -> title
        return s("kwarg", prop_name)
      });

      args = s("args", ...kwargs)
    };

    // Wrap in arrow function or regular function
    return s("def", "render", args, body)
  };

  // Convert instance variable reads to local variable reads
  on_ivar(node) {
    if (!this._erb_bufvar) return super.on_ivar(node);

    // Only transform when in ERB mode
    let ivar_name = node.children.first;
    let prop_name = (ivar_name ?? "").toString().slice(1);

    // @title -> title
    return s("lvar", prop_name)
  };

  // Handle buffer initialization: _erbout = +''; or _buf = ::String.new
  on_lvasgn(node) {
    let [name, value] = node.children;

    if (!this._erb_bufvar || !["_erbout", "_buf"].includes(name)) {
      return super.on_lvasgn(node)
    };

    // Convert to simple empty string assignment: let _erbout = ""
    return s("lvasgn", name, s("str", ""))
  };

  // Handle buffer concatenation: _erbout.<< "str" or _erbout.<<(expr)
  // Also handle _buf.append= for block expressions from Ruby2JS::Erubi
  on_send(node) {
    let [target, method, ...args] = node.children;

    // Check if this is buffer concatenation via << or append=
    if (this._erb_bufvar && target?.type === "lvar" && target.children.first === this._erb_bufvar && (method === "<<" || method === "append=")) {
      let arg = args.first;

      // Handle block attached to append= (e.g., form_for do |f| ... end)
      // The AST structure is: (send (lvar :_buf) :append= (block (send nil :form_for ...) ...))
      if (arg?.type === "block" && method === "append=") {
        let block_send = arg.children[0];
        let block_args = arg.children[1];
        let block_body = arg.children[2];

        if (block_send?.type === "send") {
          let helper_name = block_send.children[1];

          if (helper_name === "form_for") {
            return this._process_form_for(block_send, block_args, block_body)
          } else {
            return this._process_block_helper(
              helper_name,
              block_send,
              block_args,
              block_body
            )
          }
        }
      };

      // Skip nil args (shouldn't happen after above handling)
      if (arg === null && method === "append=") return null;

      // Handle .freeze calls - strip them
      if (arg?.type === "send" && arg.children[1] === "freeze") {
        arg = arg.children[0]
      };

      // Handle .to_s calls
      if (arg?.type === "send" && arg.children[1] === "to_s") {
        let inner = arg.children[0];

        // Remove unnecessary parens from ((expr))
        while (inner?.type === "begin" && inner.children.length === 1) {
          inner = inner.children.first
        };

        arg = this.process(inner);

        // Skip String() wrapper if already a string literal
        if (arg?.type !== "str") arg = s("send", null, "String", arg)
      } else if (arg) {
        arg = this.process(arg)
      };

      // Convert to += concatenation
      return s("op_asgn", s("lvasgn", this._erb_bufvar), "+", arg)
    };

    // Strip .freeze calls
    if (method === "freeze" && args.length === 0 && target) {
      return this.process(target)
    };

    // Strip .to_s calls on buffer (final return)
    if (method === "to_s" && args.length === 0 && target?.type === "lvar" && target.children.first === this._erb_bufvar) {
      return this.process(target)
    };

    // Handle form builder methods: f.text_field :name, f.submit, etc.
    if (this._erb_block_var && target?.type === "lvar" && target.children.first === this._erb_block_var) {
      return this.process_form_builder_method(method, args)
    };

    // Handle html_safe - just return the receiver (no-op in JavaScript)
    // "string".html_safe -> "string"
    if (method === "html_safe" && args.length === 0 && target) {
      return this.process(target)
    };

    // Handle raw() helper - returns the argument as-is (no-op in JavaScript)
    // raw(html) -> html
    if (method === "raw" && target === null && args.length === 1) {
      return this.process(args.first)
    };

    return super.on_send(node)
  };

  // Convert form builder method calls to HTML input elements
  process_form_builder_method(method, args) {
    let field_name, name, html, value, label;
    let model = this._erb_model_name ?? "model";

    switch (method) {
    case "text_field":
    case "email_field":
    case "password_field":
    case "hidden_field":
    case "number_field":
    case "tel_field":
    case "url_field":
    case "search_field":
    case "date_field":
    case "time_field":
    case "datetime_field":
    case "datetime_local_field":
    case "month_field":
    case "week_field":
    case "color_field":
    case "range_field":
      field_name = args.first;

      if (field_name?.type === "sym") {
        name = (field_name.children.first ?? "").toString();
        let input_type = (method ?? "").toString().replace(/_field$/m, "");
        if (input_type === "text") input_type = "text";
        if (input_type === "datetime_local") input_type = "datetime-local";

        // Build input tag with model[field] naming convention
        html = `<input type="${input_type ?? ""}" name="${model ?? ""}[${name ?? ""}]" id="${model ?? ""}_${name ?? ""}">`;
        s("str", html)
      } else {
        super.process_form_builder_method(method, args)
      };

      break;

    case "text_area":
    case "textarea":
      field_name = args.first;

      if (field_name?.type === "sym") {
        name = (field_name.children.first ?? "").toString();
        html = `<textarea name="${model ?? ""}[${name ?? ""}]" id="${model ?? ""}_${name ?? ""}"></textarea>`;
        s("str", html)
      } else {
        super.process_form_builder_method(method, args)
      };

      break;

    case "check_box":
    case "checkbox":
      field_name = args.first;

      if (field_name?.type === "sym") {
        name = (field_name.children.first ?? "").toString();
        html = `<input type="checkbox" name="${model ?? ""}[${name ?? ""}]" id="${model ?? ""}_${name ?? ""}" value="1">`;
        s("str", html)
      } else {
        super.process_form_builder_method(method, args)
      };

      break;

    case "radio_button":
      field_name = args[0];
      value = args[1];

      if (field_name?.type === "sym") {
        name = (field_name.children.first ?? "").toString();
        let val = value?.type === "sym" ? (value.children.first ?? "").toString() : (value?.children.first ?? "").toString();
        html = `<input type="radio" name="${model ?? ""}[${name ?? ""}]" id="${model ?? ""}_${name ?? ""}_${val ?? ""}" value="${val ?? ""}">`;
        s("str", html)
      } else {
        super.process_form_builder_method(method, args)
      };

      break;

    case "label":
      field_name = args.first;

      if (field_name?.type === "sym") {
        name = (field_name.children.first ?? "").toString();

        // Humanize the field name for display
        let label_text = name.tr("_", " ").capitalize;
        html = `<label for="${model ?? ""}_${name ?? ""}">${label_text ?? ""}</label>`;
        s("str", html)
      } else {
        super.process_form_builder_method(method, args)
      };

      break;

    case "select":
      field_name = args.first;

      if (field_name?.type === "sym") {
        name = (field_name.children.first ?? "").toString();
        html = `<select name="${model ?? ""}[${name ?? ""}]" id="${model ?? ""}_${name ?? ""}"></select>`;
        s("str", html)
      } else {
        super.process_form_builder_method(method, args)
      };

      break;

    case "submit":

      // f.submit or f.submit "Save"
      value = args.first;

      if (value?.type === "str") {
        label = value.children.first;
        html = `<input type="submit" value="${label ?? ""}">`
      } else {
        html = "<input type=\"submit\">"
      };

      s("str", html);
      break;

    case "button":
      value = args.first;

      if (value?.type === "str") {
        label = value.children.first;
        html = `<button type="submit">${label ?? ""}</button>`
      } else {
        html = "<button type=\"submit\">Submit</button>"
      };

      s("str", html);
      break;

    default:
      return super.process_form_builder_method(method, args)
    }
  };

  // Handle block expressions like form_for, which produce:
  // _buf.append= form_for @user do |f| ... end
  on_block(node) {
    let target, method, helper_call;

    // f.button or f.button "Click me"
    if (!this._erb_bufvar) return super.on_block(node);
    let send_node = node.children[0];
    let block_args = node.children[1];
    let block_body = node.children[2];

    // Check if this is _buf.append= with a block helper call
    if (send_node.type === "send") {
      let [target, method, helper_call] = send_node.children;

      if (target?.type === "lvar" && target.children.first === this._erb_bufvar && method === "append=" && helper_call?.type === "send") {
        let helper_name = helper_call.children[1];

        // Handle form_for and similar block helpers
        if (helper_name === "form_for") {
          return this._process_form_for(helper_call, block_args, block_body)
        };

        // Generic block helper - just process the body
        // This handles link_to with blocks, content_tag, etc.
        return this._process_block_helper(
          helper_name,
          helper_call,
          block_args,
          block_body
        )
      }
    };

    return super.on_block(node)
  };

  // Convert final buffer reference to return statement
  on_lvar(node) {
    let name = node.children.first;
    if (!this._erb_bufvar || name !== this._erb_bufvar) return super.on_lvar(node);
    return super.on_lvar(node)
  };

  // Process form_for block into JavaScript
  // Generates a form tag and processes the block body with a form builder
  _process_form_for(helper_call, block_args, block_body) {
    let model_name;

    // Extract the model from form_for @model
    let model_node = helper_call.children[2];

    if (model_node?.type === "ivar") {
      model_name = (model_node.children.first ?? "").toString().delete_prefix("@")
    };

    // Get the block parameter name (usually 'f')
    let block_param = block_args.children.first?.children.first;

    // Track the block variable so we can handle f.text_field, etc.
    let old_block_var = this._erb_block_var;
    let old_model_name = this._erb_model_name;

    // Get the block parameter if any
    this._erb_block_var = block_param;
    this._erb_model_name = model_name;

    // Build the form output
    let statements = [];

    // Add opening form tag
    let form_attrs = model_name ? ` data-model="${model_name ?? ""}"` : "";

    statements.push(s(
      "op_asgn",
      s("lvasgn", this._erb_bufvar),
      "+",
      s("str", `<form${form_attrs ?? ""}>`)
    ));

    // Process block body
    if (block_body) {
      if (block_body.type === "begin") {
        for (let child of block_body.children) {
          let processed = this.process(child);
          if (processed) statements.push(processed)
        }
      } else {
        let processed = this.process(block_body);
        if (processed) statements.push(processed)
      }
    };

    // Add closing form tag
    statements.push(s(
      "op_asgn",
      s("lvasgn", this._erb_bufvar),
      "+",
      s("str", "</form>")
    ));

    // Process block body
    this._erb_block_var = old_block_var;
    this._erb_model_name = old_model_name;

    // Return a begin node with all statements
    return s("begin", ...statements.compact)
  };

  // Process generic block helpers
  _process_block_helper(helper_name, helper_call, block_args, block_body) {
    let block_param = block_args.children.first?.children.first;
    let old_block_var = this._erb_block_var;
    this._erb_block_var = block_param;
    let statements = [];

    if (block_body) {
      if (block_body.type === "begin") {
        for (let child of block_body.children) {
          let processed = this.process(child);
          if (processed) statements.push(processed)
        }
      } else {
        let processed = this.process(block_body);
        if (processed) statements.push(processed)
      }
    };

    this._erb_block_var = old_block_var;
    if (statements.length === 0) return null;

    return statements.length === 1 ? statements.first : s(
      "begin",
      ...statements.compact
    )
  };

  // Recursively collect all instance variables in the AST
  _collect_ivars(node) {
    if (!Ruby2JS.ast_node(node)) return;
    if (node.type === "ivar") this._erb_ivars.push(node.children.first);

    for (let child of node.children) {
      if (Ruby2JS.ast_node(child)) this._collect_ivars(child)
    }
  }
};

Object.defineProperties(
  Erb.prototype,
  Object.getOwnPropertyDescriptors(SEXP)
);

registerFilter("Erb", Erb.prototype);
export default Erb;
export { Erb }
