import { convert, ast_node as astNode, parse } from '../ruby2js.js';
import { Ruby2JS } from '../ruby2js.js';
import { SvelteTemplateCompiler } from './svelte_template_compiler.mjs';
import '../filters/sfc.js';
import '../filters/camelCase.js';

export class SvelteComponentTransformer {
  #errors;
  #imports;
  #lifecycleHooks;
  #methods;
  #options;
  #source;
  #vars;

  // Result of component transformation
  static Result({ component=null, script=null, template=null, imports=null, errors=null } = {}) {
    return {component, script, template, imports, errors}
  };

  // Svelte lifecycle hook mappings (Ruby method name → Svelte)
  // Use string keys to prevent camelCase conversion during transpilation
  static LIFECYCLE_HOOKS = Object.freeze({
    on_mount: "onMount",
    on_destroy: "onDestroy",
    before_update: "beforeUpdate",
    after_update: "afterUpdate"
  });

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

    this.#options = Object.assign(
      {},
      SvelteComponentTransformer.DEFAULT_OPTIONS,
      options
    );

    this.#errors = [];
    this.#vars = [];
    this.#methods = [];
    this.#lifecycleHooks = [];

    this.#imports = {
      svelte: new Set,
      sveltekitNavigation: new Set,
      sveltekitStores: new Set,
      models: new Set
    }
  };

  // Transform the component, returning a Result
  get transform() {
    // Build conversion options with SFC and camelCase filters
    let convertOptions = Object.assign(
      {},
      this.#options,
      {template: "svelte"}
    );

    convertOptions.filters ??= [];

    // Add SFC filter for @var → let var transformation
    
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

      return SvelteComponentTransformer.Result({
        component: null,
        script: scriptJs,
        template: null,
        imports: {},
        errors: this.#errors
      })
    };

    // Analyze the Ruby code to find vars, methods, lifecycle hooks
    this.#analyzeRubyCode;

    // Transform the script
    let transformedScript = this.#transformScript(scriptJs);

    // Compile the template (convert Ruby expressions if any)
    let compiledTemplate = this.#compileTemplate(templateRaw);

    // Build the final Svelte component
    let component = this.#buildComponent(
      transformedScript,
      compiledTemplate
    );

    return SvelteComponentTransformer.Result({
      component,
      script: transformedScript,
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
        let [ast, _] = parse(rubyCode);
        if (ast) this.#analyzeAst(ast)
      } catch (e) {
        this.#errors.push({type: "parseError", message: e.message})
      }
    }
  };

  // Analyze AST to find instance variables, methods, etc.
  #analyzeAst(node) {
    if (!astNode(node)) return;
    let varName, methodName, methodNameStr, target, method, args, innerTarget, innerMethod, constName;

    switch (node.type) {
    case "ivasgn":

      // Instance variable assignment → let declaration
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
      methodNameStr = methodName.toString();

      if (methodNameStr in SvelteComponentTransformer.LIFECYCLE_HOOKS) {
        this.#lifecycleHooks.push(methodName);
        this.#imports.svelte.add(SvelteComponentTransformer.LIFECYCLE_HOOKS[methodNameStr])
      } else {
        this.#methods.push(methodName)
      };

      break;

    case "send":

      // Check for navigation/routing usage
      [target, method, ...args] = node.children;

      if (target == null) {
        switch (method) {
        case "goto":
          this.#imports.sveltekitNavigation.add("goto");
          break;

        case "invalidate":
          this.#imports.sveltekitNavigation.add("invalidate");
          break;

        case "invalidateAll":
          this.#imports.sveltekitNavigation.add("invalidateAll");
          break;

        case "prefetch":
          this.#imports.sveltekitNavigation.add("prefetch");
          break;

        case "params":
          this.#imports.sveltekitStores.add("page")
        }
      } else if (astNode(target) && target.type == "send") {
        [innerTarget, innerMethod] = target.children;

        if (innerTarget == null && innerMethod == "params") {
          this.#imports.sveltekitStores.add("page")
        }
      };

      break;

    case "const":

      // Model references
      constName = node.children.at(-1).toString();
      if (/^[A-Z]/m.test(constName)) this.#imports.models.add(constName)
    };

    // Recurse into children
    for (let child of node.children) {
      if (astNode(child)) this.#analyzeAst(child)
    }
  };

  // Transform JavaScript to Svelte style
  #transformScript(js) {
    let lines = [];

    // Build imports
    // Note: Use Array() instead of .to_a for JS compatibility (Sets)
    let svelteImports = Array.from(this.#imports.svelte).sort();

    if (svelteImports.length != 0) {
      lines.push(`import { ${svelteImports.join(", ")} } from 'svelte'`)
    };

    let navImports = Array.from(this.#imports.sveltekitNavigation).sort();

    if (navImports.length != 0) {
      lines.push(`import { ${navImports.join(", ")} } from '$app/navigation'`)
    };

    let storeImports = Array.from(this.#imports.sveltekitStores).sort();

    if (storeImports.length != 0) {
      lines.push(`import { ${storeImports.join(", ")} } from '$app/stores'`)
    };

    for (let model of this.#imports.models) {
      lines.push(`import { ${model} } from '$lib/models/${this.#toSnakeCase(model)}'`)
    };

    if (lines.length > 0) lines.push("");

    // Transform the script content
    let transformed = this.#transformScriptContent(js);
    if (transformed.length != 0) lines.push(transformed);
    return lines.join("\n")
  };

  // Transform the main script content
  #transformScriptContent(js) {
    let result = js.toString() // Use to_s instead of dup for JS compatibility (strings are immutable);

    // Transform lifecycle hooks
    for (let [rubyName, svelteName] of Object.entries(SvelteComponentTransformer.LIFECYCLE_HOOKS)) {
      // Pattern: function onMount() { ... } → onMount(() => { ... })
      // or: async function onMount() { ... } → onMount(async () => { ... })
      let camelName = this.#toCamelCase(rubyName.toString());

      result = result.replaceAll(
        new RegExp(`^(\\s*)(async )?function ${camelName}\\(\\) \\{`, "gm"),

        () => {
          let indent = RegExp.$1;
          let isAsync = RegExp.$2;
          return `${indent}${svelteName}(${isAsync}() => {`
        }
      );

      // Also handle if the method name wasn't camelCased by Ruby2JS
      result = result.replaceAll(
        new RegExp(`^(\\s*)(async )?function ${rubyName}\\(\\) \\{`, "gm"),

        () => {
          let indent = RegExp.$1;
          let isAsync = RegExp.$2;
          return `${indent}${svelteName}(${isAsync}() => {`
        }
      )
    };

    return result
  };

  // Compile the template using SvelteTemplateCompiler
  #compileTemplate(template) {
    let result = SvelteTemplateCompiler.compile(template, this.#options);

    this.#errors.concat(result.errors.map(e => ({
      type: "templateError",
      ...e
    })));

    return result.template
  };

  // Build the final Svelte component
  #buildComponent(script, template) {
    return `<script>\n${script}\n</script>\n\n${template}\n`
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
