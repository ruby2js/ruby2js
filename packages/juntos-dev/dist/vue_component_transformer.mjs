import { convert, ast_node as astNode, parse } from '../ruby2js.js';
import { Ruby2JS } from '../ruby2js.js';
import { VueTemplateCompiler } from './vue_template_compiler.mjs';
import '../filters/sfc.js';
import '../filters/camelCase.js';

export class VueComponentTransformer {
  #errors;
  #imports;
  #lifecycleHooks;
  #methods;
  #options;
  #refs;
  #source;

  // Result of component transformation
  static Result({ sfc=null, script=null, template=null, imports=null, errors=null } = {}) {
    return {sfc, script, template, imports, errors}
  };

  // Vue lifecycle hook mappings (Ruby method name → Vue composition API)
  static LIFECYCLE_HOOKS = Object.freeze({
    mounted: "onMounted",
    beforeMount: "onBeforeMount",
    updated: "onUpdated",
    beforeUpdate: "onBeforeUpdate",
    unmounted: "onUnmounted",
    beforeUnmount: "onBeforeUnmount",
    activated: "onActivated",
    deactivated: "onDeactivated",
    errorCaptured: "onErrorCaptured",
    renderTracked: "onRenderTracked",
    renderTriggered: "onRenderTriggered"
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

    this.#options = {
      ...VueComponentTransformer.DEFAULT_OPTIONS,
      ...options
    };

    this.#errors = [];
    this.#refs = [];
    this.#methods = [];
    this.#lifecycleHooks = [];
    this.#imports = {vue: new Set, vueRouter: new Set, models: new Set}
  };

  // Transform the component, returning a Result
  get transform() {
    // Build conversion options with SFC and camelCase filters
    let convertOptions = {...this.#options, template: "vue"};
    convertOptions.filters ??= [];

    // Add SFC filter for @var → const var = ref(value) transformation
    
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

      return VueComponentTransformer.Result({
        sfc: null,
        script: scriptJs,
        template: null,
        imports: {},
        errors: this.#errors
      })
    };

    // Analyze the Ruby code to find refs, methods, lifecycle hooks
    this.#analyzeRubyCode;

    // Transform the script
    let transformedScript = this.#transformScript(scriptJs);

    // Compile the template (convert Ruby expressions if any)
    let compiledTemplate = this.#compileTemplate(templateRaw);

    // Build the final SFC
    let sfc = this.#buildSfc(transformedScript, compiledTemplate);

    return VueComponentTransformer.Result({
      sfc,
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
    let varName, methodName, target, method, args, innerTarget, innerMethod, constName;

    switch (node.type) {
    case "ivasgn":

      // Instance variable assignment → ref
      varName = node.children[0].toString().slice(1) // Remove @;
      if (!this.#refs.includes(varName)) this.#refs.push(varName);
      this.#imports.vue.add("ref");
      break;

    case "ivar":
      varName = node.children[0].toString().slice(1);
      if (!this.#refs.includes(varName)) this.#refs.push(varName);
      this.#imports.vue.add("ref");
      break;

    case "def":
      methodName = node.children[0];

      if (methodName in VueComponentTransformer.LIFECYCLE_HOOKS) {
        this.#lifecycleHooks.push(methodName);
        this.#imports.vue.add(VueComponentTransformer.LIFECYCLE_HOOKS[methodName].toString())
      } else {
        this.#methods.push(methodName)
      };

      break;

    case "send":
      [target, method, ...args] = node.children;

      if (target == null) {
        switch (method) {
        case "router":
        case "navigate":
          this.#imports.vueRouter.add("useRouter");
          break;

        case "route":
        case "params":
          this.#imports.vueRouter.add("useRoute")
        }
      } else if (astNode(target) && target.type == "send") {
        [innerTarget, innerMethod] = target.children;

        if (innerTarget == null && innerMethod == "params") {
          this.#imports.vueRouter.add("useRoute")
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

  // Transform JavaScript to Vue composition API style
  #transformScript(js) {
    let lines = [];

    // Note: Use Array() instead of .to_a for JS compatibility (Sets)
    let vueImports = Array.from(this.#imports.vue).sort();

    if (vueImports.length != 0) {
      lines.push(`import { ${vueImports.join(", ")} } from 'vue'`)
    };

    let routerImports = Array.from(this.#imports.vueRouter).sort();

    if (routerImports.length != 0) {
      lines.push(`import { ${routerImports.join(", ")} } from 'vue-router'`)
    };

    for (let model of this.#imports.models) {
      lines.push(`import { ${model} } from '@/models/${this.#toSnakeCase(model)}'`)
    };

    if (lines.length > 0) lines.push("");

    // Add router/route initialization
    // Note: Use router_imports array (already converted from Set) for JS compatibility
    if (routerImports.includes("useRouter")) {
      lines.push("const router = useRouter()")
    };

    if (routerImports.includes("useRoute")) lines.push("const route = useRoute()");

    // Transform the script content
    let transformed = this.#transformScriptContent(js);
    if (transformed.length != 0) lines.push(transformed);
    return lines.join("\n")
  };

  // Transform the main script content
  #transformScriptContent(js) {
    let result = js.toString() // Use to_s instead of dup for JS compatibility (strings are immutable);

    // Transform instance variable declarations to refs
    // Pattern: let varName = value → const varName = ref(value)
    for (let refName of this.#refs) {
      let camelName = this.#toCamelCase(refName);

      // Handle initial assignment
      result = result.replaceAll(
        new RegExp(`let ${camelName} = (.+?)(;|\\n)`, "g"),

        () => {
          let value = RegExp.$1;
          return `const ${camelName} = ref(${value})${RegExp.$2}`
        }
      )
    };

    // Handle .value access for refs (in method bodies)
    // This is tricky - we need to add .value when accessing refs
    // Transform lifecycle hooks
    for (let [rubyName, vueName] of Object.entries(VueComponentTransformer.LIFECYCLE_HOOKS)) {
      // Pattern: function mounted() { ... } → onMounted(() => { ... })
      // or: async function mounted() { ... } → onMounted(async () => { ... })
      result = result.replaceAll(
        new RegExp(`^(\\s*)(async )?function ${this.#toCamelCase(rubyName.toString())}\\(\\) \\{`, "gm"),

        () => {
          let indent = RegExp.$1;
          let isAsync = RegExp.$2;
          return `${indent}${vueName}(${isAsync}() => {`
        }
      )
    };

    // Close the lifecycle hook properly
    // This is simplified - real implementation would need proper brace matching
    // Transform router.push
    result = result.replaceAll(/router\.push\(/g, "router.push(");
    return result
  };

  // Compile the template using VueTemplateCompiler
  #compileTemplate(template) {
    let result = VueTemplateCompiler.compile(template, this.#options);

    this.#errors.concat(result.errors.map(e => ({
      type: "templateError",
      ...e
    })));

    return result.template
  };

  // Build the final Vue SFC
  #buildSfc(script, template) {
    return `<script setup>
${script}
</script>

<template>
${this.#indentTemplate(template)}
</template>
`
  };

  // Indent template content for prettier output
  // Note: Use split instead of lines for JS compatibility
  // Note: Use explicit parens for JS compatibility
  #indentTemplate(template) {
    return template.split("\n").map(line => "  " + line.trimEnd()).join(`\n`).trim()
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
