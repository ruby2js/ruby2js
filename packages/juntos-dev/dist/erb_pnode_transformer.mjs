import { convert } from '../ruby2js.js';
import '../filters/esm.js';
import '../filters/functions.js';
import '../filters/return.js';
import '../filters/camelCase.js';
import '../filters/react.js';
import '../filters/jsx.js';


// Simple StringScanner implementation for ERB parsing
class StringScanner {
  constructor(source) {
    this.source = source;
    this.pos = 0;
  }

  eos() {
    return this.pos >= this.source.length;
  }

  check(pattern) {
    const match = this.source.slice(this.pos).match(pattern);
    if (match && match.index === 0) {
      return match[0];
    }
    return null;
  }

  scan(pattern) {
    const match = this.source.slice(this.pos).match(pattern);
    if (match && match.index === 0) {
      this.pos += match[0].length;
      return match[0];
    }
    return null;
  }

  scanUntil(pattern) {
    const rest = this.source.slice(this.pos);
    const match = rest.match(pattern);
    if (match) {
      const end = match.index + match[0].length;
      const result = rest.slice(0, end);
      this.pos += end;
      return result;
    }
    return null;
  }

  getch() {
    if (this.pos >= this.source.length) return null;
    return this.source[this.pos++];
  }
}

function createScanner(source) {
  return new StringScanner(source);
}

export class ErbPnodeTransformer {
  #errors;
  #options;
  #source;

  // Result of component transformation
  static Result({ component=null, script=null, template=null, errors=null } = {}) {
    return {component, script, template, errors}
  };

  // Default options
  static DEFAULT_OPTIONS = Object.freeze({
    eslevel: 2_022,
    filters: [],
    react: "React"
  });

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

  get source() {
    return this.#source
  };

  get options() {
    return this.#options
  };

  get errors() {
    return this.#errors
  };

  constructor(source, options={}) {
    this.#source = source;
    this.#options = {...ErbPnodeTransformer.DEFAULT_OPTIONS, ...options};
    this.#errors = []
  };

  // Transform the component, returning a Result
  get transform() {
    // Split source at __END__
    let parts = this.#source.split(/^__END__\r?\n?/m, 2);
    let rubyCode = parts[0];
    let erbTemplate = parts[1];

    if (erbTemplate == null || erbTemplate.trim().length == 0) {
      this.#errors.push({
        type: "noTemplate",
        message: "No __END__ template found"
      });

      return ErbPnodeTransformer.Result({
        component: null,
        script: rubyCode,
        template: null,
        errors: this.#errors
      })
    };

    // Convert ERB template to Ruby code with %x{} syntax
    let rubyJsx = this.#erbToRuby(erbTemplate.trim());

    if (this.#errors.length > 0) {
      return ErbPnodeTransformer.Result({
        component: null,
        script: rubyCode,
        template: erbTemplate,
        errors: this.#errors
      })
    };

    // Replace `render` calls with the Ruby JSX code
    let modifiedRuby = this.#injectRenderBody(rubyCode, rubyJsx);

    // Convert Ruby code to JavaScript
    let convertOptions = this.#buildConvertOptions;
    let result = convert(modifiedRuby, convertOptions);
    let jsCode = result.toString();

    // Add React import for SSR compatibility when in React mode
    if (this.#options.react == "React" && !jsCode.includes("import React")) {
      jsCode = "import React from \"react\";\n" + jsCode
    };

    return ErbPnodeTransformer.Result({
      component: jsCode,
      script: rubyCode,
      template: erbTemplate,
      errors: this.#errors
    })
  };

  // Class method for simple one-shot transformation
  static transform(source, options={}) {
    return new ErbPnodeTransformer(source, options).transform
  };

  get #buildConvertOptions() {
    let convertOptions = {...this.#options};
    convertOptions.filters ??= [];

    // Add required filters
    let filtersToAdd = [
      "ESM",
      "Functions",
      "Return",
      "CamelCase",
      "React",
      "JSX"
    ];

    for (let filter of filtersToAdd) {
      if (!convertOptions.filters.includes(filter)) {
        convertOptions.filters = convertOptions.filters.concat([filter])
      }
    };

    return convertOptions
  };

  // Convert ERB template to Ruby code (top-level)
  // At top level, we output Ruby code with %x{} around JSX
  #erbToRuby(template) {
    let scanner = createScanner(template);
    return this.#convertTopLevel(scanner)
  };

  // Convert top-level content (Ruby code mode)
  // This produces Ruby code that includes %x{} blocks for JSX
  #convertTopLevel(scanner) {
    let jsxParts;
    let parts = [];

    while (!scanner.eos) {
      scanner.match(/\s*/g);
      if (scanner.eos) break;

      // ERB control tag at top level: <% if/unless/each %>
      if (scanner.check(/<%[^=]/)) {
        parts.push(this.#convertTopErbControl(scanner))
      } else if (scanner.check(/<%=/)) {
        parts.push(this.#convertErbOutput(scanner, {topLevel: true}))
      } else if (scanner.check(/<[a-zA-Z]/)) {
        let jsx = this.#convertElement(scanner, {insideJsx: false});
        parts.push(`%x{${jsx}}`)
      } else {
        // Skip unexpected content
        scanner.getch
      }
    };

    if (parts.length == 1) {
      return parts[0]
    } else {
      // Multiple parts need to be wrapped in a fragment
      jsxParts = parts.map(part => (
        part.startsWith("%x{") ? part.slice(3, -1) : `{${part}}`
      ));

      return `%x{<>${jsxParts.join("")}</>}`
    }
  };

  // Convert an HTML element
  // inside_jsx: true means we're already inside %x{}, output raw JSX
  // inside_jsx: false means we're at top level, output will be wrapped in %x{}
  #convertElement(scanner, { insideJsx }) {
    scanner.match(/</g);
    let tag = scanner.match(/[a-zA-Z][a-zA-Z0-9-]*/g);
    if (!tag) return "";

    // Parse attributes
    let attrs = [];

    while (true) {
      scanner.match(/\s+/g);
      if (scanner.check(/\/?>/)) break;
      let name = scanner.match(/[a-zA-Z_:][-a-zA-Z0-9_:.]*/g);
      if (!name) break;

      if (scanner.match(/\s*=\s*/g)) {
        if (scanner.match(/"/g)) {
          let value = scanner.match(/[^"]*/g);
          scanner.match(/"/g);
          attrs.push(`${name}="${value}"`)
        } else if (scanner.match(/'/g)) {
          let value = scanner.match(/[^']*/g);
          scanner.match(/'/g);
          attrs.push(`${name}="${value}"`)
        } else if (scanner.match(/\{/g)) {
          let expr = this.#scanBalancedBraces(scanner);
          attrs.push(`${name}={${expr}}`)
        } else {
          let value = scanner.match(/[^\s>]+/g);
          attrs.push(`${name}="${value}"`)
        }
      } else {
        attrs.push(name)
      }
    };

    let attrStr = attrs.length == 0 ? "" : " " + attrs.join(" ");
    let $void = ErbPnodeTransformer.VOID_ELEMENTS.includes(tag.toLowerCase());

    // Self-closing?
    if (scanner.match(/\s*\/\s*>/g)) return `<${tag}${attrStr} />`;
    scanner.match(/\s*>/g);
    if ($void) return `<${tag}${attrStr} />`;

    // Parse children (we're now inside JSX)
    let children = this.#convertJsxChildren(scanner);

    // Consume closing tag
    scanner.match(new RegExp(`</${tag}\\s*>`, "g"));
    return children.length == 0 ? `<${tag}${attrStr} />` : `<${tag}${attrStr}>${children}</${tag}>`
  };

  // Convert children inside JSX (inside %x{})
  // Returns raw JSX content with {} for expressions
  #convertJsxChildren(scanner) {
    let parts = [];

    while (!scanner.eos) {
      // Check for closing tag
      if (scanner.check(/<\/[a-zA-Z]/)) break;
      let part = this.#convertJsxChild(scanner);
      if (part && part.length != 0) parts.push(part)
    };

    return parts.join("")
  };

  // Convert a single child inside JSX
  #convertJsxChild(scanner) {
    // Skip insignificant whitespace
    let ws = scanner.match(/\s*/g);
    if (scanner.eos) return null;
    if (scanner.check(/<\//)) return null;

    if (scanner.check(/<%[^=]/)) {
      return this.#convertJsxErbControl(scanner)
    } else if (scanner.check(/<%=/)) {
      return this.#convertErbOutput(scanner, {topLevel: false})
    } else if (scanner.check(/<[a-zA-Z]/)) {
      return this.#convertElement(scanner, {insideJsx: true})
    } else {
      return this.#convertText(scanner)
    }
  };

  // Convert ERB output tag: <%= expr %>
  // At top level, returns the expression; inside JSX, returns {expr}
  #convertErbOutput(scanner, { topLevel }) {
    scanner.match(/<%=\s*/g);
    let expr = scanner.scanUntil(/%>/);
    if (!expr) return "";
    expr = expr.replace(/%>$/, "").trim();
    return topLevel ? expr : `{${expr}}`
  };

  // Convert ERB control tag at top level (Ruby code mode)
  // Returns Ruby code with %x{} around JSX parts
  #convertTopErbControl(scanner) {
    scanner.match(/<%\s*/g);
    let code = scanner.scanUntil(/%>/);
    if (!code) return "";
    code = code.replace(/%>$/, "").trim();

    switch (code) {
    case /^if\s+(.+)$/m:
      return this.#convertTopIf(RegExp.$1, scanner);

    case /^unless\s+(.+)$/m:
      return this.#convertTopUnless(RegExp.$1, scanner);

    case /^(\w+(?:\.\w+)*)\.each\s+do\s*\|([^|]+)\|$/m:
      return this.#convertTopEach(RegExp.$1, RegExp.$2, scanner);

    case /^(\w+(?:\.\w+)*)\.map\s+do\s*\|([^|]+)\|$/m:
      return this.#convertTopEach(RegExp.$1, RegExp.$2, scanner);

    case "else":
    case "end":
      return code;

    default:
      return code
    }
  };

  // Convert ERB control tag inside JSX
  // Returns {expression} for use inside JSX
  #convertJsxErbControl(scanner) {
    scanner.match(/<%\s*/g);
    let code = scanner.scanUntil(/%>/);
    if (!code) return "";
    code = code.replace(/%>$/, "").trim();

    switch (code) {
    case /^if\s+(.+)$/m:
      return this.#convertJsxIf(RegExp.$1, scanner);

    case /^unless\s+(.+)$/m:
      return this.#convertJsxUnless(RegExp.$1, scanner);

    case /^(\w+(?:\.\w+)*)\.each\s+do\s*\|([^|]+)\|$/m:
      return this.#convertJsxEach(RegExp.$1, RegExp.$2, scanner);

    case /^(\w+(?:\.\w+)*)\.map\s+do\s*\|([^|]+)\|$/m:
      return this.#convertJsxEach(RegExp.$1, RegExp.$2, scanner);

    case "else":
    case "end":
      return code;

    default:
      return `{${code}}`
    }
  };

  // Convert top-level if/else/end to Ruby ternary with %x{} around JSX
  #convertTopIf(condition, scanner) {
    let thenParts = [];
    let elseParts = [];
    let inElse = false;

    while (!scanner.eos) {
      let part;
      scanner.match(/\s*/g);

      if (scanner.check(/<%\s*(else|elsif|end)\s*%>/)) {
        let marker = Array.from(
          scanner.matchAll(/<%\s*(else|elsif|end)\s*%>/g),
          s => s.slice(1)
        );

        if (/else/.test(marker)) {
          inElse = true;
          continue
        } else {
          // end
          break
        }
      };

      if (scanner.check(/<[a-zA-Z]/)) {
        let jsx = this.#convertElement(scanner, {insideJsx: false});
        part = `%x{${jsx}}`
      } else if (scanner.check(/<%=/)) {
        part = this.#convertErbOutput(scanner, {topLevel: true})
      } else if (scanner.check(/<%[^=]/)) {
        part = this.#convertTopErbControl(scanner)
      } else {
        scanner.match(/\s*/g);
        if (scanner.eos) continue;
        if (scanner.check(/<%/) || scanner.check(/</)) continue;
        scanner.getch // Skip unexpected char;
        continue
      };

      if (part && part.trim().length != 0 && part != "else" && part != "end") {
        if (inElse) {
          elseParts.push(part)
        } else {
          thenParts.push(part)
        }
      }
    };

    let thenContent = this.#wrapParts(thenParts);
    let elseContent = this.#wrapParts(elseParts);
    return elseContent.length == 0 ? `(${condition}) && (${thenContent})` : `(${condition}) ? (${thenContent}) : (${elseContent})`
  };

  // Convert top-level unless to conditional
  #convertTopUnless(condition, scanner) {
    let thenParts = [];

    while (!scanner.eos) {
      scanner.match(/\s*/g);

      if (scanner.check(/<%\s*end\s*%>/)) {
        scanner.match(/<%\s*end\s*%>/g);
        break
      };

      if (scanner.check(/<[a-zA-Z]/)) {
        let jsx = this.#convertElement(scanner, {insideJsx: false});
        thenParts.push(`%x{${jsx}}`)
      } else if (scanner.check(/<%=/)) {
        thenParts.push(this.#convertErbOutput(scanner, {topLevel: true}))
      } else if (scanner.check(/<%[^=]/)) {
        let part = this.#convertTopErbControl(scanner);
        if (part && part.trim().length != 0 && part != "end") thenParts.push(part)
      } else {
        scanner.match(/\s*/g);
        if (scanner.eos) continue;
        if (scanner.check(/<%/) || scanner.check(/</)) continue;
        scanner.getch;
        continue
      }
    };

    let thenContent = this.#wrapParts(thenParts);
    return `!(${condition}) && (${thenContent})`
  };

  // Convert top-level each/map loop
  #convertTopEach(collection, $var, scanner) {
    let bodyParts = [];
    $var = $var.trim();

    while (!scanner.eos) {
      scanner.match(/\s*/g);

      if (scanner.check(/<%\s*end\s*%>/)) {
        scanner.match(/<%\s*end\s*%>/g);
        break
      };

      if (scanner.check(/<[a-zA-Z]/)) {
        let jsx = this.#convertElement(scanner, {insideJsx: false});
        bodyParts.push(`%x{${jsx}}`)
      } else if (scanner.check(/<%=/)) {
        bodyParts.push(this.#convertErbOutput(scanner, {topLevel: true}))
      } else if (scanner.check(/<%[^=]/)) {
        let part = this.#convertTopErbControl(scanner);
        if (part && part.trim().length != 0 && part != "end") bodyParts.push(part)
      } else {
        scanner.match(/\s*/g);
        if (scanner.eos) continue;
        if (scanner.check(/<%/) || scanner.check(/</)) continue;
        scanner.getch;
        continue
      }
    };

    let bodyContent = this.#wrapParts(bodyParts);
    return `${collection}.map { |${$var}| ${bodyContent} }`
  };

  // Convert JSX if/else/end to ternary expression
  #convertJsxIf(condition, scanner) {
    let thenParts = [];
    let elseParts = [];
    let inElse = false;

    while (!scanner.eos) {
      scanner.match(/\s*/g);

      if (scanner.check(/<%\s*(else|end)\s*%>/)) {
        let marker = Array.from(
          scanner.matchAll(/<%\s*(else|end)\s*%>/g),
          s => s.slice(1)
        );

        if (/else/.test(marker)) {
          inElse = true;
          continue
        } else {
          break
        }
      };

      if (scanner.check(/<\//)) break;
      let part = this.#convertJsxChild(scanner);

      if (part && part.trim().length != 0 && part != "else" && part != "end") {
        if (inElse) {
          elseParts.push(part)
        } else {
          thenParts.push(part)
        }
      }
    };

    let thenContent = thenParts.join("");
    let elseContent = elseParts.join("");
    return elseContent.length == 0 ? `{(${condition}) && (${thenContent})}` : `{(${condition}) ? (${thenContent}) : (${elseContent})}`
  };

  // Convert JSX unless to conditional expression
  #convertJsxUnless(condition, scanner) {
    let thenParts = [];

    while (!scanner.eos) {
      scanner.match(/\s*/g);

      if (scanner.check(/<%\s*end\s*%>/)) {
        scanner.match(/<%\s*end\s*%>/g);
        break
      };

      if (scanner.check(/<\//)) break;
      let part = this.#convertJsxChild(scanner);
      if (part && part.trim().length != 0 && part != "end") thenParts.push(part)
    };

    let thenContent = thenParts.join("");
    return `{!(${condition}) && (${thenContent})}`
  };

  // Convert JSX each/map loop to expression
  #convertJsxEach(collection, $var, scanner) {
    let bodyParts = [];
    $var = $var.trim();

    while (!scanner.eos) {
      scanner.match(/\s*/g);

      if (scanner.check(/<%\s*end\s*%>/)) {
        scanner.match(/<%\s*end\s*%>/g);
        break
      };

      if (scanner.check(/<\//)) break;
      let part = this.#convertJsxChild(scanner);
      if (part && part.trim().length != 0 && part != "end") bodyParts.push(part)
    };

    let bodyContent = bodyParts.join("");
    return `{${collection}.map { |${$var}| ${bodyContent} }}`
  };

  // Wrap multiple parts appropriately
  #wrapParts(parts) {
    if (parts.length == 0) return "";
    if (parts.length == 1) return parts[0];

    // Multiple parts need fragment wrapper
    let jsxContent = parts.map(part => (
      part.startsWith("%x{") ? part.slice(3, -1) : `{${part}}`
    )).join("");

    return `%x{<>${jsxContent}</>}`
  };

  // Convert text content
  #convertText(scanner) {
    let text = +"";

    while (!scanner.eos) {
      if (scanner.check(/</) || scanner.check(/<%/)) break;
      let char = scanner.getch;
      if (char) text.push(char)
    };

    return text.trim()
  };

  // Scan balanced braces for JSX expressions
  #scanBalancedBraces(scanner) {
    let depth = 1;
    let expr = +"";

    while (!scanner.eos && depth != 0) {
      let char = scanner.getch;

      switch (char) {
      case "{":
        depth++;
        expr.push(char);
        break;

      case "}":
        depth--;
        if (depth > 0) expr.push(char);
        break;

      default:
        if (char) expr.push(char)
      }
    };

    return expr
  };

  // Inject Ruby JSX code into the Ruby source, replacing `render` calls
  #injectRenderBody(rubyCode, rubyJsx) {
    return rubyCode.replaceAll(/^\s*render\s*$/gm, (match) => {
      let indent = match.match(/^\s*/m)?.[0];
      return `${indent}${rubyJsx}`
    })
  }
}
