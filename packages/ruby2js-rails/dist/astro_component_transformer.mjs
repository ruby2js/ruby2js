import { convert } from '../ruby2js.js';
import { Ruby2JS } from '../ruby2js.js';
import { AstroTemplateCompiler } from './astro_template_compiler.mjs';
import '../filters/sfc.js';
import '../filters/camelCase.js';

export class AstroComponentTransformer {
  #errors;
  #imports;
  #methods;
  #options;
  #propNames;
  #source;
  #usesParams;
  #usesProps;
  #vars;

  // Result of component transformation
  static Result({ component=null, frontmatter=null, template=null, imports=null, errors=null } = {}) {
    return {component, frontmatter, template, imports, errors}
  };

  // Default options
  static DEFAULT_OPTIONS = Object.freeze({eslevel: 2_022, filters: []});

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

    this.#options = {
      ...AstroComponentTransformer.DEFAULT_OPTIONS,
      ...options
    };

    this.#errors = [];
    this.#vars = [];
    this.#methods = [];
    this.#imports = {models: new Set};
    this.#usesParams = false;
    this.#usesProps = false;
    this.#propNames = new Set
  };

  // Transform the component, returning a Result
  get transform() {
    // Build conversion options with SFC and camelCase filters
    let convertOptions = {...this.#options, template: "astro"};
    convertOptions.filters ??= [];

    // Add SFC filter for @var → const var transformation
    
    if (!convertOptions.filters.includes(Ruby2JS.Filter.SFC)) {
      convertOptions.filters = convertOptions.filters.concat([Ruby2JS.Filter.SFC])
    };

    // Add camelCase filter for method/variable name conversion
    
    if (!convertOptions.filters.includes(Ruby2JS.Filter.CamelCase)) {
      convertOptions.filters = convertOptions.filters.concat([Ruby2JS.Filter.CamelCase])
    };

    // Extract template from __END__
    let result = convert(this.#source, convertOptions);
    let scriptJs = result.toString();
    let templateRaw = result.template;

    if (templateRaw == null || templateRaw.length == 0) {
      this.#errors.push({
        type: "noTemplate",
        message: "No __END__ template found"
      });

      return AstroComponentTransformer.Result({
        component: null,
        frontmatter: scriptJs,
        template: null,
        imports: {},
        errors: this.#errors
      })
    };

    // Analyze the Ruby code to find vars, methods, params/props usage
    this.#analyzeRubyCode;

    // Transform the script to Astro frontmatter
    let transformedFrontmatter = this.#transformFrontmatter(scriptJs);

    // Compile the template (convert Ruby expressions if any)
    let compiledTemplate = this.#compileTemplate(templateRaw);

    // Build the final Astro component
    let component = this.#buildComponent(
      transformedFrontmatter,
      compiledTemplate
    );

    return AstroComponentTransformer.Result({
      component,
      frontmatter: transformedFrontmatter,
      template: compiledTemplate,
      imports: this.#imports,
      errors: this.#errors
    })
  };

  // Class method for simple one-shot transformation
  static transform(source, options={}) {
    return new this(source, options).transform
  };

  // Analyze Ruby source to extract component structure
  get #analyzeRubyCode() {
    // Parse just the Ruby code (before __END__)
    let rubyCode = this.#source.split(/^__END__\r?\n?/m, 2)[0];

    {
      try {
        let [ast, _] = Ruby2JS.parse(rubyCode);
        if (ast) this.#analyzeAst(ast)
      } catch (e) {
        this.#errors.push({type: "parseError", message: e.message})
      }
    }
  };

  // Analyze AST to find instance variables, methods, etc.
  #analyzeAst(node) {
    if (!node instanceof Ruby2JS.Node) return;
    let varName, methodName, target, method, args, innerTarget, innerMethod, constName;

    switch (node.type) {
    case "ivasgn":

      // Instance variable assignment → const declaration
      varName = node.children[0].toString().slice(1) // Remove @;
      if (!this.#vars.includes(varName)) this.#vars.push(varName);
      break;

    case "ivar":

      // Instance variable reference
      varName = node.children[0].toString().slice(1);
      if (!this.#vars.includes(varName)) this.#vars.push(varName);
      break;

    case "def":
      methodName = node.children[0];
      this.#methods.push(methodName);
      break;

    case "send":
      [target, method, ...args] = node.children;

      if (target == null) {
        switch (method) {
        case "params":
          this.#usesParams = true;
          break;

        case "props":
          this.#usesProps = true
        }
      } else if (target instanceof Ruby2JS.Node && target.type == "send") {
        [innerTarget, innerMethod] = target.children;

        if (innerTarget == null) {
          if (innerMethod == "params") {
            this.#usesParams = true;

            // Track which param is accessed
            if (args[0]?.type == "sym") {
              this.#propNames.add(args[0].children[0].toString())
            }
          } else if (innerMethod == "props") {
            this.#usesProps = true;

            if (args[0]?.type == "sym") {
              this.#propNames.add(args[0].children[0].toString())
            }
          }
        }
      };

      break;

    case "const":

      // Model references
      constName = node.children.at(-1).toString();
      if (/^[A-Z]/m.test(constName)) this.#imports.models.add(constName)
    };

    // Recurse into children
    // Check child is an object before checking for :type (JS compatibility)
    for (let child of node.children) {
      if (child instanceof Ruby2JS.Node) this.#analyzeAst(child)
    }
  };

  // Transform JavaScript to Astro frontmatter style
  #transformFrontmatter(js) {
    let camelNames;
    let lines = [];

    for (let model of this.#imports.models) {
      lines.push(`import { ${model} } from '../models/${this.#toSnakeCase(model)}'`)
    };

    if (lines.some(Boolean)) lines.push("");

    // Add Astro.params destructuring if params are used
    if (this.#usesParams) {
      if (this.#propNames.size > 0) {
        camelNames = [...this.#propNames].map(n => this.#toCamelCase(n));
        lines.push(`const { ${camelNames.join(", ")} } = Astro.params`)
      } else {
        lines.push("const params = Astro.params")
      }
    };

    // Add Astro.props destructuring if props are used
    if (this.#usesProps) {
      if (this.#propNames.size > 0) {
        camelNames = [...this.#propNames].map(n => this.#toCamelCase(n));
        lines.push(`const { ${camelNames.join(", ")} } = Astro.props`)
      } else {
        lines.push("const props = Astro.props")
      }
    };

    // Transform the script content
    let transformed = this.#transformScriptContent(js);
    if (transformed.length != 0) lines.push(transformed);
    return lines.join(`\n`)
  };

  // Transform the main script content
  #transformScriptContent(js) {
    let result = js.toString() // Use to_s instead of dup for JS compatibility (strings are immutable);

    result = result.replaceAll(
      /params\[:([\w]+)\]/g,
      () => this.#toCamelCase(RegExp.$1)
    );

    result = result.replaceAll(
      /params\["([\w]+)"\]/g,
      () => this.#toCamelCase(RegExp.$1)
    );

    result = result.replaceAll(
      /params\.([\w]+)/g,
      () => this.#toCamelCase(RegExp.$1)
    );

    result = result.replaceAll(
      /props\[:([\w]+)\]/g,
      () => this.#toCamelCase(RegExp.$1)
    );

    result = result.replaceAll(
      /props\["([\w]+)"\]/g,
      () => this.#toCamelCase(RegExp.$1)
    );

    result = result.replaceAll(
      /props\.([\w]+)/g,
      () => this.#toCamelCase(RegExp.$1)
    );

    return result
  };

  // Compile the template using AstroTemplateCompiler
  #compileTemplate(template) {
    let result = AstroTemplateCompiler.compile(template, this.#options);

    this.#errors.concat(result.errors.map(e => ({
      type: "templateError",
      ...e
    })));

    return result.template
  };

  // Build the final Astro component
  #buildComponent(frontmatter, template) {
    return frontmatter && frontmatter.trim().length != 0 ? `---\n${frontmatter}\n---\n\n${template}\n` : template
  };

  // Convert camelCase to snake_case
  #toSnakeCase(str) {
    return str.replaceAll(/([A-Z])/g, "_$1").toLowerCase().replace(
      /^_/m,
      ""
    )
  };

  // Convert snake_case to camelCase
  #toCamelCase(str) {
    return str.replaceAll(/_([a-z])/g, () => RegExp.$1.toUpperCase())
  }
}
