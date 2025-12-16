Object.defineProperty(
  Array.prototype,
  "first",
  {get() {return this[0]}, configurable: true}
);

import { Parser, SEXP, s, S, ast_node, include, Filter, DEFAULTS, excluded, included, _options, filterContext, nodesEqual, registerFilter, scanRegexpGroups, Ruby2JS } from "../ruby2js.js";

class ActiveSupport extends Filter.Processor {
  // ActiveSupport core extensions commonly used in Rails templates
  // https://guides.rubyonrails.org/active_support_core_extensions.html
  on_send(node) {
    let [target, method, ...args] = node.children;

    if (method === "blank?" && args.length === 0 && target) {
      // obj.blank? => obj == null || obj.length === 0 || obj === ''
      target = this.process(target);

      return s(
        "or",

        s(
          "or",
          s("send", target, "==", s("nil")),
          s("send", s("attr", target, "length"), "===", s("int", 0))
        ),

        s("send", target, "===", s("str", ""))
      )
    };

    if (method === "present?" && args.length === 0 && target) {
      target = this.process(target);

      return s(
        "and",

        s(
          "and",
          s("send", target, "!=", s("nil")),
          s("send", s("attr", target, "length"), "!=", s("int", 0))
        ),

        s("send", target, "!=", s("str", ""))
      )
    };

    if (method === "presence" && args.length === 0 && target) {
      target = this.process(target);

      let present_check = s(
        "and",

        s(
          "and",
          s("send", target, "!=", s("nil")),
          s("send", s("attr", target, "length"), "!=", s("int", 0))
        ),

        s("send", target, "!=", s("str", ""))
      );

      return s("if", present_check, target, s("nil"))
    };

    if (method === "try" && args.length >= 1 && target) {
      // obj.try(:method) => obj?.method
      // obj.try(:method, arg) => obj?.method(arg)
      let method_name = args.first;

      if (method_name.type === "sym") {
        target = this.process(target);
        let method_sym = method_name.children.first;
        let remaining_args = args.slice(1).map(a => this.process(a));

        if (remaining_args.length === 0) {
          return s("csend", target, method_sym)
        } else {
          return s("csend", target, method_sym, ...remaining_args)
        }
      }
    };

    if (method === "in?" && args.length === 1 && target) {
      target = this.process(target);
      let collection = this.process(args.first);
      return s("send", collection, "includes", target)
    };

    if (method === "squish" && args.length === 0 && target) {
      target = this.process(target);
      let trimmed = s("send", target, "trim");

      return s(
        "send",
        trimmed,
        "replace",
        s("regexp", s("str", "\\s+"), s("regopt", "g")),
        s("str", " ")
      )
    };

    if (method === "truncate" && target && args.length >= 1) {
      target = this.process(target);
      let length = this.process(args.first);
      let omission = "...";

      if (args.length > 1 && args[1].type === "hash") {
        for (let pair of args[1].children) {
          if (pair.type === "pair" && pair.children[0].type === "sym" && pair.children[0].children.first === "omission" && pair.children[1].type === "str") {
            omission = pair.children[1].children.first
          }
        }
      };

      let omission_length = omission.length;
      let slice_length = s("send", length, "-", s("int", omission_length));
      let condition = s("send", s("attr", target, "length"), ">", length);

      let truncated = s(
        "send",
        s("send", target, "slice", s("int", 0), slice_length),
        "+",
        s("str", omission)
      );

      return s("if", condition, truncated, target)
    };

    if (method === "to_sentence" && args.length === 0 && target) {
      target = this.process(target);

      // Empty case
      let empty_check = s(
        "send",
        s("attr", target, "length"),
        "===",
        s("int", 0)
      );

      // Single element case
      let single_check = s(
        "send",
        s("attr", target, "length"),
        "===",
        s("int", 1)
      );

      let single_result = s("send", target, "[]", s("int", 0));

      // Multiple elements: join all but last with ', ', add ' and ' + last
      let all_but_last = s(
        "send",
        target,
        "slice",
        s("int", 0),
        s("int", -1)
      );

      let joined = s("send", all_but_last, "join", s("str", ", "));

      let last_elem = s(
        "send",
        target,
        "[]",
        s("send", s("attr", target, "length"), "-", s("int", 1))
      );

      let multi_result = s(
        "send",
        s("send", joined, "+", s("str", " and ")),
        "+",
        last_elem
      );

      return s(
        "if",
        empty_check,
        s("str", ""),
        s("if", single_check, single_result, multi_result)
      )
    };

    // obj.present? => !(obj.blank?)
    // obj != null && obj.length !== 0 && obj !== ''
    // obj.presence => obj.present? ? obj : null
    // obj.in?(array) => array.includes(obj)
    // str.squish => str.trim().replace(/\s+/g, ' ')
    // str.truncate(n) => str.length > n ? str.slice(0, n - 3) + '...' : str
    // str.truncate(n, omission: '...') => custom omission
    // arr.to_sentence => arr.length === 0 ? '' :
    //   arr.length === 1 ? arr[0] :
    //   arr.slice(0, -1).join(', ') + ' and ' + arr[arr.length - 1]
    return super.on_send(node)
  }
};

Object.defineProperties(
  ActiveSupport.prototype,
  Object.getOwnPropertyDescriptors(SEXP)
);

registerFilter("ActiveSupport", ActiveSupport.prototype);
export default ActiveSupport;
export { ActiveSupport }
