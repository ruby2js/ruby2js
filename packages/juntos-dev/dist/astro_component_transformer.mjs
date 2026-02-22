import { convert, ast_node as astNode, parse } from '../ruby2js.js';
import { Ruby2JS } from '../ruby2js.js';
import { AstroTemplateCompiler } from './astro_template_compiler.mjs';
import '../filters/esm.js';
import '../filters/functions.js';
import '../filters/return.js';
import '../filters/sfc.js';
import '../filters/camelCase.js';

export class AstroComponentTransformer {
  #errors;
  #imports;
  #options;
  #source;

  // Result of component transformation
  static Result({ component=null, frontmatter=null, template=null, errors=null } = {}) {
    return {component, frontmatter, template, errors}
  };

  // Default options
  static DEFAULT_OPTIONS = Object.freeze({
    eslevel: 2_022,
    filters: [],
    autoImports: true
  });

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

    this.#options = Object.assign(
      {},
      AstroComponentTransformer.DEFAULT_OPTIONS,
      options
    );

    this.#errors = [];
    this.#imports = {models: new Set}
  };

  // Transform the component, returning a Result
  get transform() {
    // Build conversion options with SFC and camelCase filters
    let convertOptions = Object.assign(
      {},
      this.#options,
      {template: "astro"}
    );

    convertOptions.filters ??= [];

    // Add ESM filter for import/export handling
    
    if (!convertOptions.filters.includes(Ruby2JS.Filter.ESM)) {
      convertOptions.filters = [
        ...convertOptions.filters,
        ...[Ruby2JS.Filter.ESM]
      ]
    };

    // Add functions filter for method parentheses (.pop → .pop())
    
    if (!convertOptions.filters.includes(Ruby2JS.Filter.Functions)) {
      convertOptions.filters = [
        ...convertOptions.filters,
        ...[Ruby2JS.Filter.Functions]
      ]
    };

    // Add return filter for implicit returns in blocks
    
    if (!convertOptions.filters.includes(Ruby2JS.Filter.Return)) {
      convertOptions.filters = [
        ...convertOptions.filters,
        ...[Ruby2JS.Filter.Return]
      ]
    };

    // Add SFC filter for @var → const var transformation
    
    if (!convertOptions.filters.includes(Ruby2JS.Filter.SFC)) {
      convertOptions.filters = [
        ...convertOptions.filters,
        ...[Ruby2JS.Filter.SFC]
      ]
    };

    // Add camelCase filter for method/variable name conversion
    
    if (!convertOptions.filters.includes(Ruby2JS.Filter.CamelCase)) {
      convertOptions.filters = [
        ...convertOptions.filters,
        ...[Ruby2JS.Filter.CamelCase]
      ]
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
        errors: this.#errors
      })
    };

    // Analyze the Ruby code to find model references
    this.#analyzeRubyCode;

    // The converted JS is already transformed by filters (ESM, SFC, etc.)
    // Prepend model imports if any were detected
    let transformedFrontmatter = this.#prependModelImports(scriptJs);

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
      errors: this.#errors
    })
  };

  // Class method for simple one-shot transformation
  static transform(source, options={}) {
    return new this(source, options).transform
  };

  // Analyze Ruby source to extract model references
  get #analyzeRubyCode() {
    // Parse just the Ruby code (before __END__)
    let rubyCode = this.#source.split(/^__END__\r?\n?/m, 2)[0];

    {
      try {
        let [ast, _] = parse(rubyCode);
        if (ast) this.#analyzeAst(ast)
      } catch (e) {
        this.#errors.push({type: "parseError", message: e.message})
      }
    }
  };

  // Framework-provided constants that should not be auto-imported
  static FRAMEWORK_CONSTANTS = Object.freeze(["Astro"]);

  // Analyze AST to find model references (capitalized constants)
  #analyzeAst(node) {
    if (!astNode(node)) return;
    let constName;

    switch (node.type) {
    case "const":

      // Model references - any capitalized constant except framework globals
      constName = node.children.at(-1).toString();

      if (/^[A-Z]/m.test(constName) && !AstroComponentTransformer.FRAMEWORK_CONSTANTS.includes(constName)) {
        this.#imports.models.add(constName)
      }
    };

    // Recurse into children
    for (let child of node.children) {
      if (astNode(child)) this.#analyzeAst(child)
    }
  };

  // Prepend model imports to the frontmatter
  #prependModelImports(js) {
    if (this.#imports.models.length == 0) return js;
    if (!this.#options.autoImports) return js;
    let lines = [];

    for (let model of this.#imports.models) {
      lines.push(`import { ${model} } from '../models/${this.#toSnakeCase(model)}'`)
    };

    lines.push("");
    lines.push(js);
    return lines.join(`\n`)
  };

  // Convert CamelCase to snake_case
  #toSnakeCase(str) {
    return str.replaceAll(/([A-Z])/g, "_$1").toLowerCase().replace(
      /^_/m,
      ""
    )
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
  }
}
