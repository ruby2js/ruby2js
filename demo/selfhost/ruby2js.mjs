#!/usr/bin/env node
// Ruby2JS JavaScript CLI - uses selfhosted converter
//
// Usage:
//   node ruby2js.mjs [options] [file]
//   echo "puts 'hello'" | node ruby2js.mjs [options]
//
// See --help for full options

import * as fs from 'fs';

// Import runtime classes (transpiled from lib/ruby2js/selfhost/runtime.rb)
import {
  Prism,
  PrismSourceBuffer,
  PrismSourceRange,
  PrismComment,
  CommentsMap,
  associateComments,
  Hash,
  setupGlobals,
  initPrism
} from './dist/runtime.mjs';

import { Namespace } from './dist/namespace.mjs';

// Set up globals and initialize Prism BEFORE importing walker/converter
// (they depend on Prism being available as a global)
setupGlobals();
globalThis.Namespace = Namespace;
const prismParse = await initPrism();

// Import walker and converter (must be after setupGlobals)
const { Ruby2JS: WalkerModule } = await import('./dist/walker.mjs');
const { Ruby2JS: ConverterModule } = await import('./dist/converter.mjs');

// Set up Ruby2JS global
globalThis.Ruby2JS = { Node: WalkerModule.Node };

// ============================================================================
// AST Formatting and Inspection
// ============================================================================

// Format Prism AST node for display (verbose mode shows all properties)
function formatPrismNode(node, indent = '', options = {}) {
  const { verbose = false, showLoc = false } = options;

  if (node === null || node === undefined) return `${indent}null`;
  if (typeof node !== 'object') return `${indent}${JSON.stringify(node)}`;
  if (Array.isArray(node)) {
    if (node.length === 0) return `${indent}[]`;
    const items = node.map(item => formatPrismNode(item, indent + '  ', options));
    return `${indent}[\n${items.join(',\n')}\n${indent}]`;
  }

  // Check if it's a Prism node (has constructor with name)
  const type = node.constructor?.name || 'Object';

  // Skip location objects for brevity unless showLoc is true
  if (!showLoc && (type.endsWith('Location') || type === 'Location')) {
    if (node.startOffset !== undefined) {
      return `${indent}<${type} ${node.startOffset}-${node.startOffset + (node.length || 0)}>`;
    }
    return `${indent}<${type}>`;
  }

  // For AST nodes, show type and relevant properties
  const props = [];
  for (const [key, value] of Object.entries(node)) {
    // Skip internal properties unless verbose
    if (!verbose && key.startsWith('_')) continue;
    // Skip location properties unless showLoc
    if (!showLoc && (key === 'location' || key.endsWith('Loc'))) continue;
    if (value === null || value === undefined) continue;

    const formatted = formatPrismNode(value, indent + '  ', options);
    if (formatted.includes('\n')) {
      props.push(`${indent}  ${key}:\n${formatted}`);
    } else {
      props.push(`${indent}  ${key}: ${formatted.trim()}`);
    }
  }

  if (props.length === 0) return `${indent}(${type})`;
  return `${indent}(${type}\n${props.join('\n')}\n${indent})`;
}

// Inspect a single Prism node - show ALL properties with types
function inspectPrismNode(node) {
  if (!node || typeof node !== 'object') {
    return `Value: ${JSON.stringify(node)} (${typeof node})`;
  }

  const type = node.constructor?.name || 'Object';
  const lines = [`Node Type: ${type}`, ''];

  // Get all own properties
  const allProps = Object.getOwnPropertyNames(node);
  // Also get prototype methods that look like getters
  const proto = Object.getPrototypeOf(node);
  const protoProps = proto ? Object.getOwnPropertyNames(proto).filter(p => {
    if (p === 'constructor' || p.startsWith('_')) return false;
    const desc = Object.getOwnPropertyDescriptor(proto, p);
    return desc && (desc.get || typeof desc.value === 'function');
  }) : [];

  lines.push('Own Properties:');
  for (const key of allProps.sort()) {
    const value = node[key];
    const valueType = value === null ? 'null' :
                      value === undefined ? 'undefined' :
                      Array.isArray(value) ? `Array[${value.length}]` :
                      typeof value === 'object' ? value.constructor?.name || 'Object' :
                      typeof value;
    const preview = typeof value === 'string' ? `"${value.slice(0, 50)}"` :
                    typeof value === 'boolean' || typeof value === 'number' ? String(value) :
                    valueType;
    lines.push(`  ${key}: ${preview} (${valueType})`);
  }

  if (protoProps.length > 0) {
    lines.push('');
    lines.push('Prototype Methods/Getters:');
    for (const key of protoProps.sort()) {
      try {
        const desc = Object.getOwnPropertyDescriptor(proto, key);
        if (desc.get) {
          const value = node[key];
          const valueType = value === null ? 'null' :
                            value === undefined ? 'undefined' :
                            Array.isArray(value) ? `Array[${value.length}]` :
                            typeof value === 'object' ? value.constructor?.name || 'Object' :
                            typeof value;
          const preview = typeof value === 'string' ? `"${value.slice(0, 50)}"` :
                          typeof value === 'boolean' || typeof value === 'number' ? String(value) :
                          valueType;
          lines.push(`  ${key}: ${preview} (${valueType}) [getter]`);
        } else if (typeof desc.value === 'function') {
          lines.push(`  ${key}() [method]`);
        }
      } catch (e) {
        lines.push(`  ${key}: <error: ${e.message}>`);
      }
    }
  }

  return lines.join('\n');
}

// Find nodes matching a type pattern in Prism AST
function findPrismNodes(node, pattern, results = [], path = 'root') {
  if (!node || typeof node !== 'object') return results;

  const type = node.constructor?.name || '';
  const regex = new RegExp(pattern, 'i');

  if (regex.test(type)) {
    results.push({ path, type, node });
  }

  // Recurse into arrays
  if (Array.isArray(node)) {
    node.forEach((child, i) => findPrismNodes(child, pattern, results, `${path}[${i}]`));
  } else {
    // Recurse into object properties
    for (const [key, value] of Object.entries(node)) {
      if (key.startsWith('_') || key === 'location') continue;
      if (value && typeof value === 'object') {
        findPrismNodes(value, pattern, results, `${path}.${key}`);
      }
    }
  }

  return results;
}

// Format Ruby2JS AST node (Parser-compatible format)
function formatAst(node, indent = '') {
  if (node === null || node === undefined) return 'nil';
  if (typeof node !== 'object' || !node.type) {
    return JSON.stringify(node);
  }

  const type = node.type;
  const children = node.children || [];

  if (children.length === 0) {
    return `s(:${type})`;
  }

  // Check if any children are AST nodes
  const hasNodeChildren = children.some(c => c && typeof c === 'object' && c.type);

  if (!hasNodeChildren) {
    // All primitives - single line
    return `s(:${type}, ${children.map(c => JSON.stringify(c)).join(', ')})`;
  }

  // Multi-line format
  const lines = [`s(:${type},`];
  children.forEach((child, i) => {
    const comma = i < children.length - 1 ? ',' : '';
    if (child && typeof child === 'object' && child.type) {
      const formatted = formatAst(child, indent + '  ');
      lines.push(`${indent}  ${formatted}${comma}`);
    } else {
      lines.push(`${indent}  ${JSON.stringify(child)}${comma}`);
    }
  });
  lines.push(`${indent})`);
  return lines.join('\n');
}

// ============================================================================
// Argument Parsing
// ============================================================================

const args = process.argv.slice(2);
let outputMode = 'js';  // default
let eslevel = 2020;
let file = null;
let searchPattern = null;
let inspectPath = null;
let verbose = false;
let showLoc = false;

for (let i = 0; i < args.length; i++) {
  const arg = args[i];

  if (arg === '--ast') {
    outputMode = 'prism-ast';
  } else if (arg === '--walker-ast') {
    outputMode = 'walker-ast';
  } else if (arg === '--js') {
    outputMode = 'js';
  } else if (arg.startsWith('--eslevel=')) {
    eslevel = parseInt(arg.split('=')[1], 10);
  } else if (arg === '--verbose' || arg === '-v') {
    verbose = true;
  } else if (arg === '--loc') {
    showLoc = true;
  } else if (arg === '--find' || arg === '-f') {
    searchPattern = args[++i];
    outputMode = 'find';
  } else if (arg.startsWith('--find=')) {
    searchPattern = arg.split('=')[1];
    outputMode = 'find';
  } else if (arg === '--inspect' || arg === '-i') {
    inspectPath = args[++i] || 'root';
    outputMode = 'inspect';
  } else if (arg.startsWith('--inspect=')) {
    inspectPath = arg.split('=')[1];
    outputMode = 'inspect';
  } else if (arg === '--help' || arg === '-h') {
    console.log(`Ruby2JS JavaScript CLI - uses selfhosted converter

Usage:
  node ruby2js.mjs [options] [file]
  echo "puts 'hello'" | node ruby2js.mjs [options]

Output Modes:
  --js              Output JavaScript (default)
  --ast             Output raw Prism AST
  --walker-ast      Output AST after walker (Parser-compatible s-expression)
  --find=PATTERN    Find nodes matching PATTERN (regex) in Prism AST
  --inspect=PATH    Inspect node at PATH (e.g., "root.statements.body[0]")

Options:
  --eslevel=NNNN    Set ECMAScript level (default: 2020)
  --verbose, -v     Show all properties including internal ones
  --loc             Show location information
  --help, -h        Show this help

Examples:
  # Convert Ruby to JavaScript
  echo "puts 'hello'" | node ruby2js.mjs

  # View Prism AST
  echo "self.p ||= 1" | node ruby2js.mjs --ast

  # View walker output (s-expression)
  echo "self.p ||= 1" | node ruby2js.mjs --walker-ast

  # Find all nodes containing "Write" in type name
  echo "self.p ||= 1" | node ruby2js.mjs --find=Write

  # Inspect a specific node to see all its properties
  echo "self.p ||= 1" | node ruby2js.mjs --inspect=root.statements.body[0]

  # Verbose AST output (shows internal properties)
  echo "@a = 1" | node ruby2js.mjs --ast --verbose`);
    process.exit(0);
  } else if (!arg.startsWith('-')) {
    file = arg;
  }
}

// ============================================================================
// Read Source and Execute
// ============================================================================

let source;
if (file) {
  source = fs.readFileSync(file, 'utf-8');
} else if (process.stdin.isTTY) {
  console.error('Error: No input. Provide a file or pipe Ruby code via stdin.');
  console.error('Use --help for usage information.');
  process.exit(1);
} else {
  source = fs.readFileSync(0, 'utf-8');
}

try {
  // Parse with Prism
  const parseResult = prismParse(source);

  if (parseResult.errors && parseResult.errors.length > 0) {
    console.error('Parse error:', parseResult.errors[0].message);
    process.exit(1);
  }

  if (outputMode === 'prism-ast') {
    console.log(formatPrismNode(parseResult.value, '', { verbose, showLoc }));

  } else if (outputMode === 'find') {
    const matches = findPrismNodes(parseResult.value, searchPattern);
    if (matches.length === 0) {
      console.log(`No nodes matching "${searchPattern}" found.`);
    } else {
      console.log(`Found ${matches.length} node(s) matching "${searchPattern}":\n`);
      for (const match of matches) {
        console.log(`--- ${match.path} (${match.type}) ---`);
        console.log(inspectPrismNode(match.node));
        console.log('');
      }
    }

  } else if (outputMode === 'inspect') {
    // Navigate to the specified path
    let node = parseResult.value;
    const parts = inspectPath.split(/\.|\[|\]/).filter(Boolean);

    if (parts[0] === 'root') parts.shift();

    for (const part of parts) {
      if (node === null || node === undefined) {
        console.error(`Path "${inspectPath}" not found (stopped at null/undefined)`);
        process.exit(1);
      }
      if (/^\d+$/.test(part)) {
        node = node[parseInt(part, 10)];
      } else {
        node = node[part];
      }
    }

    console.log(`Inspecting: ${inspectPath}\n`);
    console.log(inspectPrismNode(node));

  } else if (outputMode === 'walker-ast') {
    const walker = new WalkerModule.PrismWalker(source, file);
    const ast = walker.visit(parseResult.value);
    console.log(formatAst(ast));

  } else {
    // Full conversion to JavaScript
    const walker = new WalkerModule.PrismWalker(source, file);
    const ast = walker.visit(parseResult.value);

    // Use walker's source buffer for comment association
    // This ensures AST nodes and comments share the same buffer reference
    const sourceBuffer = walker.source_buffer;

    // Wrap and associate comments with AST nodes
    const wrappedComments = (parseResult.comments || []).map(
      c => new PrismComment(c, source, sourceBuffer)
    );
    const comments = associateComments(ast, wrappedComments);

    const converter = new ConverterModule.Converter(ast, comments, {});
    converter.eslevel = eslevel;
    converter.underscored_private = true;
    converter.namespace = new Namespace();

    converter.convert;
    console.log(converter.to_s);
  }
} catch (e) {
  console.error('Error:', e.message);
  if (process.env.DEBUG) {
    console.error(e.stack);
  }
  process.exit(1);
}
