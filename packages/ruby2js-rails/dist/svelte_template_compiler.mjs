import { convert } from '../ruby2js.js';
import { Ruby2JS } from '../ruby2js.js';
import '../filters/camelCase.js';
import '../filters/functions.js';

export class SvelteTemplateCompiler {
  #errors;
  #options;
  #template;
  #warnings;

  // Result of template compilation
  static Result({ template=null, errors=null, warnings=null } = {}) {
    return {template, errors, warnings}
  };

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

    this.#options = {
      ...SvelteTemplateCompiler.DEFAULT_OPTIONS,
      ...options
    };

    this.#errors = [];
    this.#warnings = []
  };

  get compile() {
    let result = [];
    let pos = 0;

    while (pos < this.#template.length) {
      // Find next { that's not escaped
      let braceStart = this.#findNextBrace(this.#template, pos);

      if (braceStart == null) {
        // No more braces, add remaining text
        result.push(this.#template.slice(pos));
        break
      };

      // Add text before brace
      if (braceStart > pos) result.push(this.#template.slice(pos, braceStart));
      let braceEnd = this.#findMatchingBrace(this.#template, braceStart);

      if (braceEnd == null) {
        this.#errors.push({type: "unmatchedBrace", position: braceStart});
        result.push(this.#template.slice(braceStart));
        break
      };

      // Extract content between braces
      let content = this.#template.slice(braceStart + 1, braceEnd);
      result.push("{", this.#processBraceContent(content), "}");
      pos = braceEnd + 1
    };

    return SvelteTemplateCompiler.Result({
      template: result.join(""),
      errors: this.#errors,
      warnings: this.#warnings
    })
  };

  // Class method for simple one-shot compilation
  static compile(template, options={}) {
    return new this(template, options).compile
  };

  #findNextBrace(str, startPos) {
    let pos = startPos;

    while (pos < str.length) {
      let idx = str.indexOf("{", pos);
      if (idx === -1) return null;

      if (idx > 0 && str[idx - 1] == "\\") {
        pos = idx + 1;
        continue
      };

      return idx
    };

    return null
  };

  #findMatchingBrace(str, openPos) {
    let depth = 1;
    let pos = openPos + 1;
    let inString = null;
    let escapeNext = false;

    while (pos < str.length && depth > 0) {
      let char = str[pos];

      if (escapeNext) {
        escapeNext = false;
        pos++;
        continue
      };

      if (char == "\\") {
        escapeNext = true;
        pos++;
        continue
      };

      if (inString) {
        if (char == inString) inString = null
      } else {
        switch (char) {
        case "\"":
        case "'":
          inString = char;
          break;

        case "`":
          inString = char;
          break;

        case "{":
          depth++;
          break;

        case "}":
          depth--
        }
      };

      pos++
    };

    return depth == 0 ? pos - 1 : null
  };

  #processBraceContent(content) {
    content = content.trim();

    if (/^#each\s+(.+?)\s+as\s+(.+)$/m.test(content)) {
      return this.#processEachBlock(RegExp.$1, RegExp.$2)
    } else if (/^#if\s+(.+)$/m.test(content)) {
      return this.#processIfBlock(RegExp.$1)
    } else if (/^:else\s+if\s+(.+)$/m.test(content)) {
      return this.#processElseIfBlock(RegExp.$1)
    } else if (/^:else$/m.test(content)) {
      return content
    } else if (/^\/each$/m.test(content) || /^\/if$/m.test(content) || /^\/await$/m.test(content) || /^\/key$/m.test(content)) {
      return content
    } else if (/^#await\s+(.+)$/m.test(content)) {
      return this.#processAwaitBlock(RegExp.$1)
    } else if (/^:then\s*(.*)$/m.test(content)) {
      return this.#processThenBlock(RegExp.$1)
    } else if (/^:catch\s*(.*)$/m.test(content)) {
      return this.#processCatchBlock(RegExp.$1)
    } else if (/^#key\s+(.+)$/m.test(content)) {
      return this.#processKeyBlock(RegExp.$1)
    } else if (/^@html\s+(.+)$/m.test(content)) {
      return `@html ${this.#convertExpression(RegExp.$1)}`
    } else if (/^@debug\s+(.+)$/m.test(content)) {
      return `@debug ${this.#convertExpression(RegExp.$1)}`
    } else if (/^@const\s+(\w+)\s*=\s*(.+)$/m.test(content)) {
      return `@const ${RegExp.$1} = ${this.#convertExpression(RegExp.$2)}`
    } else {
      {
        try {
          return this.#convertExpression(content)
        } catch (e) {
          this.#errors.push({type: "expression", content, error: e.message});
          return content
        }
      }
    }
  };

  // Process {#each collection as item} or {#each collection as item, index (key)}
  #processEachBlock(collectionExpr, asClause) {
    let vars, keyExpr, jsKey;
    let jsCollection = this.#convertExpression(collectionExpr.trim());

    if (/^(.+?)\s*\((.+)\)$/m.test(asClause)) {
      vars = RegExp.$1.trim();
      keyExpr = RegExp.$2.trim();
      jsKey = this.#convertExpression(keyExpr);
      return `#each ${jsCollection} as ${vars} (${jsKey})`
    } else {
      return `#each ${jsCollection} as ${asClause.trim()}`
    }
  };

  // Process {#if condition}
  #processIfBlock(condition) {
    let jsCondition = this.#convertExpression(condition.trim());
    return `#if ${jsCondition}`
  };

  // Process {:else if condition}
  #processElseIfBlock(condition) {
    let jsCondition = this.#convertExpression(condition.trim());
    return `:else if ${jsCondition}`
  };

  // Process {#await promise}
  #processAwaitBlock(promiseExpr) {
    let jsPromise = this.#convertExpression(promiseExpr.trim());
    return `#await ${jsPromise}`
  };

  // Process {:then value}
  #processThenBlock(value) {
    return value.trim().length == 0 ? ":then" : `:then ${value.trim()}`
  };

  // Process {:catch error}
  #processCatchBlock(error) {
    return error.trim().length == 0 ? ":catch" : `:catch ${error.trim()}`
  };

  // Process {#key expression}
  #processKeyBlock(expression) {
    let jsExpr = this.#convertExpression(expression.trim());
    return `#key ${jsExpr}`
  };

  // Convert a Ruby expression to JavaScript using Ruby2JS
  #convertExpression(rubyExpr) {
    let convertOptions = {
      eslevel: this.#options.eslevel,
      filters: this.#buildFilters
    };

    // Wrap expression in array - [expr] becomes [jsExpr] in JS
    // This prevents bare identifiers from being treated as declarations
    let wrapped = `[${rubyExpr}]`;
    let result = convert(wrapped, convertOptions);
    let js = result.toString().trim();

    // Remove trailing semicolon
    js = js.chomp(";").trim();
    if (js.startsWith("[") && js.endsWith("]")) js = js.slice(1, -1).trim();
    return js
  };

  get #buildFilters() {
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
