import { convert } from '../ruby2js.js';
import { Ruby2JS } from '../ruby2js.js';
import '../filters/camelCase.js';
import '../filters/functions.js';

export class AstroTemplateCompiler {
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

    this.#options = {
      ...AstroTemplateCompiler.DEFAULT_OPTIONS,
      ...options
    };

    this.#errors = [];
    this.#warnings = []
  };

  get compile() {
    // First pass: convert snake_case attribute names to camelCase
    let processed = this.#convertAttributeNames(this.#template);

    // Second pass: process {expression} blocks
    let result = [];
    let pos = 0;

    while (pos < processed.length) {
      // Find next { that's not escaped
      let braceStart = this.#findNextBrace(processed, pos);

      if (braceStart == null) {
        result.push(processed.slice(pos));
        break
      };

      if (braceStart > pos) result.push(processed.slice(pos, braceStart));
      let braceEnd = this.#findMatchingBrace(processed, braceStart);

      if (braceEnd == null) {
        // Unmatched brace - treat as literal
        this.#errors.push({type: "unmatchedBrace", position: braceStart});
        result.push(processed.slice(braceStart));
        break
      };

      // Extract content between braces
      let content = processed.slice(braceStart + 1, braceEnd);
      result.push("{", this.#processExpression(content), "}");
      pos = braceEnd + 1
    };

    return AstroTemplateCompiler.Result({
      template: result.join(""),
      errors: this.#errors,
      warnings: this.#warnings
    })
  };

  // Class method for simple one-shot compilation
  static compile(template, options={}) {
    return new this(template, options).compile
  };

  // e.g., show_count={true} → showCount={true}
  #convertAttributeNames(template) {
    let camelCaseEnabled = this.#options.camelCase ?? true;
    if (!camelCaseEnabled) return template;

    return template.replaceAll(
      /(\s)([a-z][a-z0-9]*(?:_[a-z0-9]+)+)(=)/g,

      () => {
        let space = RegExp.$1;
        let attrName = RegExp.$2;
        let equals = RegExp.$3;

        let camelName = attrName.replaceAll(
          /_([a-z0-9])/g,
          () => RegExp.$1.toUpperCase()
        );

        return `${space}${camelName}${equals}`
      }
    )
  };

  // Find the next unescaped opening brace
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

  #processExpression(content) {
    let collection, blockVars, blockBody;
    content = content.trim();

    // Handle spread operator: {...obj}
    if (content.startsWith("...")) {
      let expr = content.slice(3).trim();
      return `...${this.#convertExpression(expr)}`
    };

    // Handle Ruby block with JSX: collection.map { |item| <jsx> }
    // Pattern: expr.map { |var| jsx_content } or expr.map { |var, idx| jsx_content }
    if (/^(.+?)\.map\s*\{\s*\|([^|]+)\|\s*(.+)\s*\}$/s.test(content)) {
      collection = RegExp.$1.trim();
      blockVars = RegExp.$2.trim();
      blockBody = RegExp.$3.trim();

      if (blockBody.startsWith("<")) {
        return this.#processMapBlock(collection, blockVars, blockBody)
      }
    };

    // Handle .each (convert to .map for JSX output)
    if (/^(.+?)\.each\s*\{\s*\|([^|]+)\|\s*(.+)\s*\}$/s.test(content)) {
      collection = RegExp.$1.trim();
      blockVars = RegExp.$2.trim();
      blockBody = RegExp.$3.trim();

      if (blockBody.startsWith("<")) {
        return this.#processMapBlock(collection, blockVars, blockBody)
      }
    };

    // Handle .select/.filter with block
    if (/^(.+?)\.(select|filter)\s*\{\s*\|([^|]+)\|\s*(.+)\s*\}$/s.test(content)) {
      collection = RegExp.$1.trim();
      let method = RegExp.$2;
      let blockVar = RegExp.$3.trim();
      blockBody = RegExp.$4.trim();
      let jsCollection = this.#convertExpression(collection);
      let jsBody = this.#convertExpression(blockBody);
      return `${jsCollection}.filter(${blockVar} => ${jsBody})`
    };

    {
      // Regular expression - use begin/rescue with explicit returns for JS compatibility
      try {
        return this.#convertExpression(content)
      } catch (e) {
        this.#errors.push({type: "expression", content, error: e.message});
        return content
      }
    }
  };

  // Process a .map block with JSX body
  #processMapBlock(collection, blockVars, jsxBody) {
    let jsCollection = this.#convertExpression(collection);

    // Process the JSX body recursively (convert {expr} inside it)
    let processedBody = this.#processJsxBody(jsxBody);
    return `${jsCollection}.map(${blockVars} => ${processedBody})`
  };

  // Process JSX body, converting {expr} expressions inside it
  #processJsxBody(jsx) {
    let result = [];
    let pos = 0;

    while (pos < jsx.length) {
      let braceStart = this.#findNextBrace(jsx, pos);

      if (braceStart == null) {
        result.push(jsx.slice(pos));
        break
      };

      if (braceStart > pos) result.push(jsx.slice(pos, braceStart));
      let braceEnd = this.#findMatchingBrace(jsx, braceStart);

      if (braceEnd == null) {
        result.push(jsx.slice(braceStart));
        break
      };

      let content = jsx.slice(braceStart + 1, braceEnd);
      result.push("{", this.#processExpression(content), "}");
      pos = braceEnd + 1
    };

    return result.join("")
  };

  // Convert a Ruby expression to JavaScript using Ruby2JS
  #convertExpression(rubyExpr) {
    if (rubyExpr.length == 0) return rubyExpr;

    // Build options for Ruby2JS
    let convertOptions = {
      eslevel: this.#options.eslevel,
      filters: this.#buildFilters
    };

    // Wrap expression in array - [expr] becomes [jsExpr] in JS
    // This prevents bare identifiers from being treated as declarations
    let wrapped = `[${rubyExpr}]`;

    // Convert the wrapped expression
    let result = convert(wrapped, convertOptions);
    let js = result.toString().trim();

    // Remove trailing semicolon
    js = js.chomp(";").trim();
    if (js.startsWith("[") && js.endsWith("]")) js = js.slice(1, -1).trim();
    return js
  };

  get #buildFilters() {
    let filters = [...this.#options.filters];

    // Add camelCase filter if enabled (default)
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
