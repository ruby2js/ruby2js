// ERB File Transformer
//
// Transforms .erb.rb files (Ruby + ERB template) into JSX components.
// Uses ErbToJsx for template conversion and Ruby2JS for Ruby code.
//
// Input format (.erb.rb):
//   import hooks from 'react'
//
//   def MyComponent()
//     state, setState = useState('')
//     render
//   end
//
//   export default MyComponent
//   __END__
//   <div><%= state %></div>
//
// Output format (.jsx):
//   import React from "react";
//   import {useState} from "react";
//   function MyComponent() {
//     const [state, setState] = useState('');
//     return <div>{state}</div>;
//   }
//   export default MyComponent;

import { convert, initPrism } from '../ruby2js.js';
import { ErbToJsx } from './erb_to_jsx.mjs';
import '../filters/functions.js';
import '../filters/camelCase.js';
import '../filters/return.js';
import '../filters/esm.js';
import '../filters/react.js';
import '../filters/jsx.js';

// Unique placeholder that won't appear in normal code
const JSX_PLACEHOLDER = '___JSX_TEMPLATE_PLACEHOLDER___';

export class ErbFileTransformer {
  constructor(source, options = {}) {
    this.source = source;
    this.options = {
      eslevel: 2022,
      react: 'React',
      ...options
    };
    this.errors = [];
  }

  static async transform(source, options = {}) {
    await initPrism();
    return new ErbFileTransformer(source, options).transform();
  }

  transform() {
    // Split source at __END__
    const parts = this.source.split(/^__END__\r?\n?/m);
    const rubyCode = parts[0];
    const erbTemplate = parts[1];

    if (!erbTemplate || !erbTemplate.trim()) {
      this.errors.push({ type: 'noTemplate', message: 'No __END__ template found' });
      return {
        component: null,
        script: rubyCode,
        template: null,
        errors: this.errors
      };
    }

    try {
      // Convert ERB template to JSX using the simple converter
      const jsxTemplate = ErbToJsx.convert(erbTemplate.trim(), this.options);

      // Replace `render` calls with a placeholder string
      // The placeholder will be replaced with actual JSX after Ruby2JS conversion
      const modifiedRuby = this.injectRenderPlaceholder(rubyCode);

      // Convert Ruby code to JavaScript
      const jsCode = this.convertRubyToJs(modifiedRuby);

      // Replace the placeholder with actual JSX
      // The placeholder appears as a string in the JS output, we need to replace
      // the entire expression including quotes/parens
      const jsWithJsx = this.replacePlaceholderWithJsx(jsCode, jsxTemplate);

      // Add React import if needed
      const finalCode = this.addReactImport(jsWithJsx);

      return {
        component: finalCode,
        script: rubyCode,
        template: erbTemplate,
        errors: this.errors
      };
    } catch (e) {
      this.errors.push({ type: 'transform', message: e.message || String(e), stack: e.stack });
      return {
        component: null,
        script: rubyCode,
        template: erbTemplate,
        errors: this.errors
      };
    }
  }

  injectRenderPlaceholder(rubyCode) {
    // Replace bare `render` calls with a return of the placeholder string
    // Ruby2JS will convert this to: return "___JSX_TEMPLATE_PLACEHOLDER___"
    return rubyCode.replace(/^\s*render\s*$/gm, (match) => {
      const indent = match.match(/^\s*/)[0];
      return `${indent}"${JSX_PLACEHOLDER}"`;
    });
  }

  convertRubyToJs(rubyCode) {
    const result = convert(rubyCode, {
      eslevel: this.options.eslevel,
      filters: ['ESM', 'Functions', 'Return', 'CamelCase', 'React', 'JSX']
    });
    return result.toString();
  }

  replacePlaceholderWithJsx(jsCode, jsxTemplate) {
    // The placeholder appears in the output as either:
    // - return "___JSX_TEMPLATE_PLACEHOLDER___"
    // - "___JSX_TEMPLATE_PLACEHOLDER___"
    // We want to replace it with: return <jsx>...</jsx>
    // But we need to handle quotes properly

    // First try: replace quoted placeholder (standard case)
    const quotedPlaceholder = `"${JSX_PLACEHOLDER}"`;
    if (jsCode.includes(quotedPlaceholder)) {
      // Wrap JSX in parens if it starts with { to avoid issues
      const wrappedJsx = jsxTemplate.startsWith('{') ? `(${jsxTemplate})` : jsxTemplate;
      return jsCode.replace(quotedPlaceholder, wrappedJsx);
    }

    // Fallback: try single quotes
    const singleQuotedPlaceholder = `'${JSX_PLACEHOLDER}'`;
    if (jsCode.includes(singleQuotedPlaceholder)) {
      const wrappedJsx = jsxTemplate.startsWith('{') ? `(${jsxTemplate})` : jsxTemplate;
      return jsCode.replace(singleQuotedPlaceholder, wrappedJsx);
    }

    // If placeholder not found, return as-is (shouldn't happen)
    return jsCode;
  }

  addReactImport(jsCode) {
    // Add React import for SSR compatibility if not already present
    if (this.options.react === 'React' && !jsCode.includes('import React')) {
      return `import React from "react";\n${jsCode}`;
    }
    return jsCode;
  }
}

export default ErbFileTransformer;
