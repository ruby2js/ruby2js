// Minimal ERB runtime for browser
// Compiles ERB templates to JavaScript functions at runtime

export function compileERB(template) {
  // Convert ERB to a JavaScript function
  // Handles: <%= expr %>, <% code %>, and <%- expr %> (unescaped)

  let code = 'let __output = "";\n';
  let pos = 0;

  while (pos < template.length) {
    const erbStart = template.indexOf('<%', pos);

    if (erbStart === -1) {
      // No more ERB tags, add remaining text
      const text = template.slice(pos);
      if (text) {
        code += `__output += ${JSON.stringify(text)};\n`;
      }
      break;
    }

    // Add text before ERB tag
    if (erbStart > pos) {
      const text = template.slice(pos, erbStart);
      code += `__output += ${JSON.stringify(text)};\n`;
    }

    // Find end of ERB tag
    const erbEnd = template.indexOf('%>', erbStart);
    if (erbEnd === -1) {
      throw new Error('Unclosed ERB tag');
    }

    const tag = template.slice(erbStart + 2, erbEnd).trim();

    if (tag.startsWith('=')) {
      // Output expression: <%= expr %>
      const expr = tag.slice(1).trim();
      code += `__output += escapeHTML(${expr});\n`;
    } else if (tag.startsWith('-')) {
      // Unescaped output: <%- expr %>
      const expr = tag.slice(1).trim();
      code += `__output += (${expr});\n`;
    } else {
      // Code block: <% code %>
      // Handle each/end blocks
      if (tag.includes('.each')) {
        // Convert Ruby each to JS forEach
        const match = tag.match(/(\S+)\.each\s+do\s+\|(\w+)\|/);
        if (match) {
          code += `for (const ${match[2]} of ${match[1]}) {\n`;
        } else {
          code += `${tag}\n`;
        }
      } else if (tag === 'end') {
        code += '}\n';
      } else if (tag.startsWith('if ')) {
        code += `if (${tag.slice(3)}) {\n`;
      } else if (tag.startsWith('elsif ')) {
        code += `} else if (${tag.slice(6)}) {\n`;
      } else if (tag === 'else') {
        code += '} else {\n';
      } else {
        code += `${tag};\n`;
      }
    }

    pos = erbEnd + 2;
  }

  code += 'return __output;';

  // Create function with locals as parameters
  return new Function('locals', 'escapeHTML', `
    with (locals || {}) {
      ${code}
    }
  `);
}

// HTML escape helper
export function escapeHTML(str) {
  if (str === null || str === undefined) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

// View registry and renderer
const viewCache = new Map();
const viewTemplates = new Map();

export function registerView(name, template) {
  viewTemplates.set(name, template);
  viewCache.delete(name); // Clear cached compiled version
}

export function renderView(name, locals = {}) {
  let compiledFn = viewCache.get(name);

  if (!compiledFn) {
    const template = viewTemplates.get(name);
    if (!template) {
      throw new Error(`View not found: ${name}`);
    }
    compiledFn = compileERB(template);
    viewCache.set(name, compiledFn);
  }

  return compiledFn(locals, escapeHTML);
}

// Layout support
let layoutTemplate = null;

export function setLayout(template) {
  layoutTemplate = template;
}

export function renderWithLayout(name, locals = {}) {
  const content = renderView(name, locals);

  if (layoutTemplate) {
    const layoutFn = compileERB(layoutTemplate);
    // yield is replaced with the content
    return layoutFn({ ...locals, yield: content }, escapeHTML);
  }

  return content;
}

// Export Views object for compatibility
export const Views = {
  register: registerView,
  render: renderWithLayout,
  setLayout
};
