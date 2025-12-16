Object.defineProperty(
  Object.prototype,
  "to_a",
  {get() {return Object.entries(this)}, configurable: true}
);

Object.defineProperty(
  Array.prototype,
  "first",
  {get() {return this[0]}, configurable: true}
);

Object.defineProperty(Array.prototype, "compact", {
  get() {
    return this.filter(x => x !== null && x !== undefined)
  },

  configurable: true
});

import { Parser, SEXP, s, S, ast_node, include, Filter, DEFAULTS, excluded, included, _options, filterContext, nodesEqual, registerFilter, scanRegexpGroups, Ruby2JS } from "../ruby2js.js";

// Phlex filter for Ruby2JS
//
// Transforms Phlex component classes into JavaScript render functions.
// This is an ERB-replacement level implementation - components generate
// HTML strings but do not support component composition.
//
// Status: BETA
//
// Supported features:
// - HTML5 elements (void and standard)
// - Static and dynamic attributes
// - Nested elements
// - Loops (@items.each { |item| ... })
// - Conditionals (if/unless)
// - Instance variables as destructured parameters
// - Special methods: plain, unsafe_raw, whitespace, comment, doctype
//
// Detection:
// - Classes inheriting from Phlex::HTML or Phlex::SVG
// - Classes with `# @ruby2js phlex` pragma (for indirect inheritance)
//
// Limitations (planned for future):
// - Component composition (render OtherComponent.new)
// - Slots
// - Streaming
//
// Example:
//   class CardComponent < Phlex::HTML
//     def initialize(title:)
//       @title = title
//     end
//
//     def view_template
//       div(class: "card") do
//         h1 { @title }
//       end
//     end
//   end
//
// Outputs:
//   class CardComponent {
  //     render({ title }) {
    //       let _phlex_out = "";
    //       _phlex_out += `<div class="card">`;
    //       _phlex_out += `<h1>${String(title)}</h1>`;
    //       _phlex_out += `</div>`;
    //       return _phlex_out;
    //     }
    //   }
    class Phlex extends Filter.Processor {
      // HTML5 void elements (self-closing)
      static VOID_ELEMENTS = Object.freeze([
        "area",
        "base",
        "br",
        "col",
        "embed",
        "hr",
        "img",
        "input",
        "link",
        "meta",
        "param",
        "source",
        "track",
        "wbr"
      ]);

      // Standard HTML5 elements
      static HTML_ELEMENTS = Object.freeze([
        "a",
        "abbr",
        "address",
        "article",
        "aside",
        "audio",
        "b",
        "bdi",
        "bdo",
        "blockquote",
        "body",
        "button",
        "canvas",
        "caption",
        "cite",
        "code",
        "colgroup",
        "data",
        "datalist",
        "dd",
        "del",
        "details",
        "dfn",
        "dialog",
        "div",
        "dl",
        "dt",
        "em",
        "fieldset",
        "figcaption",
        "figure",
        "footer",
        "form",
        "h1",
        "h2",
        "h3",
        "h4",
        "h5",
        "h6",
        "head",
        "header",
        "hgroup",
        "html",
        "i",
        "iframe",
        "ins",
        "kbd",
        "label",
        "legend",
        "li",
        "main",
        "map",
        "mark",
        "menu",
        "meter",
        "nav",
        "noscript",
        "object",
        "ol",
        "optgroup",
        "option",
        "output",
        "p",
        "picture",
        "pre",
        "progress",
        "q",
        "rp",
        "rt",
        "ruby",
        "s",
        "samp",
        "script",
        "section",
        "select",
        "slot",
        "small",
        "span",
        "strong",
        "style",
        "sub",
        "summary",
        "sup",
        "table",
        "tbody",
        "td",
        "template",
        "textarea",
        "tfoot",
        "th",
        "thead",
        "time",
        "title",
        "tr",
        "u",
        "ul",
        "var",
        "video"
      ]);

      static ALL_ELEMENTS = Object.freeze(Phlex.VOID_ELEMENTS + Phlex.HTML_ELEMENTS);

      // Phlex special methods
      static PHLEX_METHODS = Object.freeze([
        "plain",
        "unsafe_raw",
        "whitespace",
        "comment",
        "doctype"
      ]);

      constructor(...args) {
        this._phlex_context = false;
        this._phlex_buffer = null;
        this._phlex_ivars = null;
        super(...args)
      };

      // Detect Phlex component class definition
      on_class(node) {
        let [name, parent, body] = node.children;

        // Check if this should be treated as a Phlex component
        if (this._phlex_component(node, parent)) {
          this._phlex_context = true;
          this._phlex_ivars = new Set;

          // Collect all instance variables used in the class
          this._collect_ivars(body);
          let result = super.on_class(node);
          this._phlex_context = false;
          this._phlex_ivars = null;
          return result
        };

        return super.on_class(node)
      };

      // Handle method definitions within Phlex context
      on_def(node) {
        let render_args;
        if (!this._phlex_context) return super.on_def(node);
        let [method_name, args, body] = node.children;

        // Transform view_template or template method to render
        if (["view_template", "template"].includes(method_name)) {
          this._phlex_buffer = "_phlex_out";

          // Build destructured parameters from collected ivars
          if (this._phlex_ivars && this._phlex_ivars.length !== 0) {
            let kwargs = this._phlex_ivars.to_a.sort().map((ivar) => {
              let prop_name = (ivar ?? "").toString().slice(1);

              // @title -> title
              return s("kwarg", prop_name)
            });

            render_args = s("args", ...kwargs)
          } else {
            render_args = s("args")
          };

          // Transform the body
          let transformed_body = this.process(body);

          // Wrap in buffer initialization and return
          let init = s("lvasgn", this._phlex_buffer, s("str", ""));
          let ret = s("return", s("lvar", this._phlex_buffer));

          let new_body = transformed_body ? s(
            "begin",
            init,
            transformed_body,
            ret
          ) : s("begin", init, ret);

          let result = s("def", "render", render_args, new_body);
          this._phlex_buffer = null;
          return result
        };

        // Skip initialize method (ivars become render params instead)
        if (method_name === "initialize") return null;
        return super.on_def(node)
      };

      // Convert instance variable reads to local variable reads
      on_ivar(node) {
        if (!this._phlex_buffer) return super.on_ivar(node);
        let ivar_name = node.children.first;
        let prop_name = (ivar_name ?? "").toString().slice(1);

        // @title -> title
        return s("lvar", prop_name)
      };

      // Handle element method calls
      on_send(node) {
        if (!this._phlex_buffer) return super.on_send(node);
        let [target, method, ...args] = node.children;

        // Only handle calls with no receiver (element methods)
        if (target !== null) return super.on_send(node);

        if (Phlex.ALL_ELEMENTS.includes(method)) {
          return this._process_element(method, args, null)
        };

        if (Phlex.PHLEX_METHODS.includes(method)) {
          return this._process_phlex_method(method, args)
        };

        return super.on_send(node)
      };

      // Handle element calls with blocks (including loops)
      on_block(node) {
        if (!this._phlex_buffer) return super.on_block(node);
        let [send_node, block_args, block_body] = node.children;
        if (send_node.type !== "send") return super.on_block(node);
        let [target, method, ...args] = send_node.children;

        // Handle element with block (div { ... })
        if (target === null && Phlex.ALL_ELEMENTS.includes(method)) {
          return this._process_element(method, args, block_body)
        };

        // For loops (.each, .map, etc.), let other filters handle the conversion
        // but ensure the body is processed for Phlex elements
        return super.on_block(node)
      };

      // Handle conditionals
      on_if(node) {
        if (!this._phlex_buffer) return super.on_if(node);

        // Process normally - Ruby2JS handles if/unless conversion
        // We just need to make sure the body is processed for elements
        let [condition, if_body, else_body] = node.children;
        let processed_condition = this.process(condition);
        let processed_if = if_body ? this.process(if_body) : null;
        let processed_else = else_body ? this.process(else_body) : null;
        return s("if", processed_condition, processed_if, processed_else)
      };

      _phlex_component(node, parent) {
        // Direct inheritance from Phlex::HTML or Phlex::SVG
        if (this._phlex_parent(parent)) return true;

        // Check for pragma: # @ruby2js phlex
        // This enables Phlex transformation for indirect inheritance:
        //   # @ruby2js phlex
        //   class Card < ApplicationComponent
        let raw_comments = this._comments["_raw"] ?? [];

        let class_line = (() => {
          try {
            node.loc?.line
          } catch {
            null
          }
        })();

        return raw_comments.some((comment) => {
          let text = typeof comment === "object" && comment !== null && "text" in comment ? comment.text : (comment ?? "").toString();

          let comment_line = (() => {
            try {
              comment.loc?.line
            } catch {
              null
            }
          })();

          // Check if comment contains the pragma and is near the class definition
          return text.includes("@ruby2js phlex") ? class_line === null || comment_line === null || (comment_line >= class_line - 1 && comment_line <= class_line) : false
        })
      };

      _phlex_parent(node) {
        let parent, name;

        // Pragma on line immediately before or same line as class
        if (!node) return false;

        // Check for Phlex::HTML or Phlex::SVG
        if (node.type === "const") {
          let [parent, name] = node.children;

          if (parent?.type === "const" && parent.children === [null, "Phlex"]) {
            return ["HTML", "SVG"].includes(name)
          }
        };

        return false
      };

      // Recursively collect all instance variables in the AST
      _collect_ivars(node) {
        if (typeof node !== "object" || node === null || !("type" in node)) return;
        if (node.type === "ivar") this._phlex_ivars.push(node.children.first);

        for (let child of node.children) {
          if (typeof child === "object" && child !== null && "type" in child) {
            this._collect_ivars(child)
          }
        }
      };

      _process_element(tag, args, block_body) {
        let close_tag;
        let tag_str = (tag ?? "").toString();
        let $void = Phlex.VOID_ELEMENTS.includes(tag);

        // Extract attributes hash if present
        let attrs_node = args.find(a => (
          typeof a === "object" && a !== null && "type" in a && a.type === "hash"
        ));

        let statements = [];

        // Build the opening tag (may be dynamic if has dynamic attrs)
        let open_tag = this._build_open_tag(tag_str, attrs_node);

        statements.push(s(
          "op_asgn",
          s("lvasgn", this._phlex_buffer),
          "+",
          open_tag
        ));

        // Process block content for non-void elements
        if (!$void) {
          if (block_body) {
            let content = this._process_block_content(block_body);
            if (content?.some(Boolean)) statements.concat(content)
          };

          // Add closing tag
          close_tag = s("str", `</${tag_str ?? ""}>`);

          statements.push(s(
            "op_asgn",
            s("lvasgn", this._phlex_buffer),
            "+",
            close_tag
          ))
        };

        return statements.length === 1 ? statements.first : s(
          "begin",
          ...statements
        )
      };

      _build_open_tag(tag_str, attrs_node) {
        if (attrs_node?.type !== "hash") return s("str", `<${tag_str ?? ""}>`);
        let static_attrs = [];
        let dynamic_attrs = [];

        for (let pair of attrs_node.children) {
          if (pair.type !== "pair") continue;
          let [key_node, value_node] = pair.children;

          // Get the attribute name
          let key = (() => {
            switch (key_node.type) {
            case "sym":
              return (key_node.children.first ?? "").toString();

            case "str":
              return key_node.children.first;

            default:
              continue
            }
          })();

          // Handle special attribute names
          if (key === "class_name") key = "class";
          key = key.tr("_", "-");

          // data_foo -> data-foo
          // Categorize as static or dynamic
          switch (value_node.type) {
          case "str":
            let value = value_node.children.first;
            static_attrs.push(`${key ?? ""}="${this._escape_html(value) ?? ""}"`);
            break;

          case "sym":
            value = (value_node.children.first ?? "").toString();
            static_attrs.push(`${key ?? ""}="${this._escape_html(value) ?? ""}"`);
            break;

          case "true":
            static_attrs.push(key);
            break;

          case "false":
            ;
            break;

          default:

            // Skip false boolean attributes
            // Dynamic value
            dynamic_attrs.push([key, value_node])
          }
        };

        // If no dynamic attributes, return simple string
        if (dynamic_attrs.length === 0) {
          let attrs_str = static_attrs.length === 0 ? "" : " " + static_attrs.join(" ");
          return s("str", `<${tag_str ?? ""}${attrs_str ?? ""}>`)
        };

        // Build template literal with interpolation for dynamic values
        // `<tag static="val" dynamic="${expr}">`
        let parts = [`<${tag_str ?? ""}`];
        if (static_attrs.length !== 0) parts.push(" " + static_attrs.join(" "));

        for (let [key, value_node] of dynamic_attrs) {
          parts.push(` ${key ?? ""}="`)
        };

        // Close current string, add interpolation, continue
        // For dynamic attributes, we need dstr (interpolated string)
        let children = [];
        children.push(s("str", `<${tag_str ?? ""}`));

        if (static_attrs.length !== 0) {
          children.push(s("str", " " + static_attrs.join(" ")))
        };

        for (let [key, value_node] of dynamic_attrs) {
          children.push(s("str", ` ${key ?? ""}="`));
          children.push(s("begin", this.process(value_node)));
          children.push(s("str", "\""))
        };

        children.push(s("str", ">"));
        return s("dstr", ...children)
      };

      _process_block_content(node) {
        if (!node) return [];
        let statements = [];

        switch (node.type) {
        case "begin":

          for (let child of node.children) {
            let result = this._process_content_node(child);

            if (Array.isArray(result)) {
              statements.concat(result)
            } else if (result) {
              statements.push(result)
            }
          };

          break;

        default:
          let result = this._process_content_node(node);

          if (Array.isArray(result)) {
            statements.concat(result)
          } else if (result) {
            statements.push(result)
          }
        };

        return statements
      };

      _process_content_node(node) {
        let prop_name, target, method, args, processed;
        if (!node) return null;

        switch (node.type) {
        case "str":

          // String literal content
          return s("op_asgn", s("lvasgn", this._phlex_buffer), "+", node);

        case "dstr":

          // Interpolated string
          return s(
            "op_asgn",
            s("lvasgn", this._phlex_buffer),
            "+",
            this.process(node)
          );

        case "ivar":

          // Instance variable - convert to local and stringify
          prop_name = (node.children.first ?? "").toString().slice(1);

          s(
            "op_asgn",
            s("lvasgn", this._phlex_buffer),
            "+",
            s("send", null, "String", s("lvar", prop_name))
          );

          break;

        case "lvar":

          // Local variable - stringify
          return s(
            "op_asgn",
            s("lvasgn", this._phlex_buffer),
            "+",
            s("send", null, "String", node)
          );

        case "send":
          let [target, method, ...args] = node.children;

          if (target === null && Phlex.ALL_ELEMENTS.includes(method)) {
            // Nested element without block
            [this._process_element(method, args, null)]
          } else if (target === null && Phlex.PHLEX_METHODS.includes(method)) {
            [this._process_phlex_method(method, args)]
          } else {
            // Other method call - process and add to buffer if it returns something
            processed = this.process(node);

            s(
              "op_asgn",
              s("lvasgn", this._phlex_buffer),
              "+",
              s("send", null, "String", processed)
            )
          };

          break;

        case "block":
          processed = this.process(node);

          // Could be nested element with block or a loop
          [processed].compact;
          break;

        case "if":

          // Conditional - process it
          return [this.process(node)];

        default:
          processed = this.process(node);
          [processed].compact
        }
      };

      _process_phlex_method(method, args) {
        let arg;

        switch (method) {
        case "plain":

          // plain "text" or plain variable - stringify and add
          arg = args.first;

          if (arg) {
            s(
              "op_asgn",
              s("lvasgn", this._phlex_buffer),
              "+",
              s("send", null, "String", this.process(arg))
            )
          };

          break;

        case "unsafe_raw":
          arg = args.first;
          if (arg) s("op_asgn", s("lvasgn", this._phlex_buffer), "+", this.process(arg));
          break;

        case "whitespace":

          // unsafe_raw "html" - add without escaping or String()
          return s(
            "op_asgn",
            s("lvasgn", this._phlex_buffer),
            "+",
            s("str", " ")
          );

        case "comment":
          arg = args.first;

          if (arg) {
            if (arg.type === "str") {
              let text = arg.children.first;

              s(
                "op_asgn",
                s("lvasgn", this._phlex_buffer),
                "+",
                s("str", `<!-- ${text ?? ""} -->`)
              )
            } else {
              // Dynamic comment
              s("op_asgn", s("lvasgn", this._phlex_buffer), "+", s(
                "dstr",
                s("str", "<!-- "),
                s("begin", this.process(arg)),
                s("str", " -->")
              ))
            }
          };

          break;

        case "doctype":

          return s(
            "op_asgn",
            s("lvasgn", this._phlex_buffer),
            "+",
            s("str", "<!DOCTYPE html>")
          )
        }
      };

      _escape_html(str) {
        return (str ?? "").toString().replaceAll("&", "&amp;").replaceAll(
          "<",
          "&lt;"
        ).replaceAll(">", "&gt;").replaceAll("\"", "&quot;")
      }
    };

    Object.defineProperties(
      Phlex.prototype,
      Object.getOwnPropertyDescriptors(SEXP)
    );

    registerFilter("Phlex", Phlex.prototype);
    export default Phlex;
    export { Phlex }
