import { convert } from '../ruby2js.js';
import { Ruby2JS } from '../ruby2js.js';
import '../filters/camelCase.js';
import '../filters/functions.js';

export class VueTemplateCompiler {
  #errors;
  #options;
  #template;
  #warnings;

  // Result of template compilation
  static Result({ template=null, errors=null, warnings=null } = {}) {
    return {template, errors, warnings}
  };

  // Default options for Ruby2JS conversion
  static DEFAULT_OPTIONS = Object.freeze({eslevel: 2_022, filters: []});

  get template() {
    return this.#template
  };

  get options() {
    return this.#options
  };

  get errors() {
    return this.#errors
  };

  get warnings() {
    return this.#warnings
  };

  constructor(template, options={}) {
    this.#template = template;
    this.#options = {...VueTemplateCompiler.DEFAULT_OPTIONS, ...options};
    this.#errors = [];
    this.#warnings = []
  };

  get compile() {
    let result = this.#template.toString() // Use to_s instead of dup for JS compatibility;

    // Process Vue interpolations: {{ expression }}
    result = this.#processInterpolations(result);
    result = this.#processVFor(result);
    result = this.#processConditionals(result);
    result = this.#processBindings(result);
    result = this.#processVModel(result);

    return VueTemplateCompiler.Result({
      template: result,
      errors: this.#errors,
      warnings: this.#warnings
    })
  };

  // Class method for simple one-shot compilation
  static compile(template, options={}) {
    return new this(template, options).compile
  };

  #processInterpolations(template) {
    return template.replaceAll(/\{\{\s*(.+?)\s*\}\}/gs, (match, $1) => {
      let rubyExpr = $1;
      let result = null;

      try {
        let jsExpr = this.#convertExpression(rubyExpr);
        result = `{{ ${jsExpr} }}`
      } catch (e) {
        this.#errors.push({
          type: "interpolation",
          expression: rubyExpr,
          error: e.message
        });

        result = match
      };

      return result
    })
  };

  // Process v-for="item in collection" and v-for="(item, index) in collection"
  #processVFor(template) {
    return template.replaceAll(
      /v-for="(.+?)\s+in\s+(.+?)"/g, (match, $1, $2) => {
        let vars = $1;
        let rubyCollection = $2.trim();
        let result = null;

        try {
          let jsCollection = this.#convertExpression(rubyCollection);
          result = `v-for="${vars} in ${jsCollection}"`
        } catch (e) {
          this.#errors.push({
            type: "vFor",
            expression: rubyCollection,
            error: e.message
          });

          result = match
        };

        return result
      }
    )
  };

  // Process v-if, v-else-if, v-show conditionals
  #processConditionals(template) {
    let result = template.replaceAll(/v-if="(.+?)"/g, (match, $1) => {
      let rubyExpr = $1;
      return this.#processDirectiveExpression("v-if", rubyExpr, match)
    });

    // Process v-else-if="condition"
    result = result.replaceAll(/v-else-if="(.+?)"/g, (match, $1) => {
      let rubyExpr = $1;
      return this.#processDirectiveExpression("v-else-if", rubyExpr, match)
    });

    // Process v-show="condition"
    result = result.replaceAll(/v-show="(.+?)"/g, (match, $1) => {
      let rubyExpr = $1;
      return this.#processDirectiveExpression("v-show", rubyExpr, match)
    });

    return result
  };

  #processBindings(template) {
    let result = template.replaceAll(
      /(?<!:):(\w[\w-]*)="(.+?)"/g, (match, $1, $2) => {
        let prop = $1;
        let rubyValue = $2;
        let replacement = null;

        try {
          let jsValue = this.#convertExpression(rubyValue);
          replacement = `:${prop}="${jsValue}"`
        } catch (e) {
          this.#errors.push({
            type: "binding",
            prop,
            expression: rubyValue,
            error: e.message
          });

          replacement = match
        };

        return replacement
      }
    );

    // Process v-bind:prop="value"
    result = result.replaceAll(/v-bind:(\w[\w-]*)="(.+?)"/g, (match, $1, $2) => {
      let prop = $1;
      let rubyValue = $2;
      let replacement = null;

      try {
        let jsValue = this.#convertExpression(rubyValue);
        replacement = `v-bind:${prop}="${jsValue}"`
      } catch (e) {
        this.#errors.push({
          type: "vBind",
          prop,
          expression: rubyValue,
          error: e.message
        });

        replacement = match
      };

      return replacement
    });

    return result
  };

  #processVModel(template) {
    return template.replaceAll(/v-model="(.+?)"/g, (match, $1) => {
      let rubyRef = $1 // Store result in variable to ensure proper return in transpiled JS;
      let result = null;

      try {
        let jsRef = this.#convertExpression(rubyRef);
        result = `v-model="${jsRef}"`
      } catch (e) {
        this.#errors.push({
          type: "vModel",
          expression: rubyRef,
          error: e.message
        });

        result = match
      };

      return result
    })
  };

  // Helper to process a directive with an expression
  #processDirectiveExpression(directive, rubyExpr, original) {
    let result = null;

    try {
      let jsExpr = this.#convertExpression(rubyExpr);
      result = `${directive}="${jsExpr}"`
    } catch (e) {
      this.#errors.push({
        type: directive,
        expression: rubyExpr,
        error: e.message
      });

      result = original
    };

    return result
  };

  #convertExpression(rubyExpr) {
    // in a context where variables already exist (reactive refs, props, etc.)
    //
    // Strategy: Wrap in an array literal and extract the first element.
    // This avoids the issue of bare identifiers being treated as declarations.
    // Build options for Ruby2JS
    let convertOptions = {
      eslevel: this.#options.eslevel,
      filters: this.#buildFilters
    };

    // Wrap expression in array - [expr] becomes [jsExpr] in JS
    let wrapped = `[${rubyExpr}]`;
    let result = convert(wrapped, convertOptions);
    let js = result.toString().trim();

    // Remove trailing semicolon
    js = js.chomp(";").trim();
    if (js.startsWith("[") && js.endsWith("]")) js = js.slice(1, -1).trim();
    return js
  };

  get #buildFilters() {
    // Note: Use spread [...] instead of .dup for JS compatibility
    let filters = [...this.#options.filters];
    let camelCaseEnabled = this.#options.camelCase ?? true;

    if (camelCaseEnabled) {
      
      if (!filters.includes(Ruby2JS.Filter.CamelCase)) {
        filters.push(Ruby2JS.Filter.CamelCase)
      }
    };

    // Add functions filter for common Ruby->JS method conversions
    
    if (!filters.includes(Ruby2JS.Filter.Functions)) {
      filters.push(Ruby2JS.Filter.Functions)
    };

    return filters
  }
}
