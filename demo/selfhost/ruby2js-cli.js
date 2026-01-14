#!/usr/bin/env node
// Ruby2JS CLI
// This is a thin wrapper around the ruby2js.js library

import { convert, Ruby2JS, initPrism, PrismComment, associateComments } from './ruby2js.js';
import fs from 'fs';
import { fileURLToPath } from 'url';
import path from 'path';

// Suppress the "WASI is an experimental feature" warning from @ruby/prism
if (typeof process !== 'undefined' && process.emit) {
  const originalEmit = process.emit.bind(process);
  process.emit = function(event, ...args) {
    if (event === 'warning' && args[0]?.name === 'ExperimentalWarning' &&
        args[0]?.message?.includes('WASI')) {
      return false;
    }
    return originalEmit(event, ...args);
  };
}

// ============================================================================
// AST Formatting (for --ast, --prism-ast, --find, --inspect modes)
// ============================================================================

function formatPrismNode(node, indent = '', options = {}, seen = null) {
  const verbose = options.verbose || false;
  const showLoc = options.showLoc || false;
  seen = seen || [];

  if (node === null || node === undefined) return `${indent}null`;
  if (typeof node !== 'object') return `${indent}${JSON.stringify(node)}`;

  if (seen.includes(node)) return `${indent}[Circular]`;
  seen.push(node);

  if (Array.isArray(node)) {
    if (node.length === 0) return `${indent}[]`;
    const items = node.map(item => formatPrismNode(item, indent + '  ', options, seen));
    return `${indent}[\n${items.join(',\n')}\n${indent}]`;
  }

  const type = node.constructor?.name || 'Object';

  if (!showLoc && (type.endsWith('Location') || type === 'Location')) {
    if (node.startOffset !== undefined) {
      return `${indent}<${type} ${node.startOffset}-${node.startOffset + (node.length || 0)}>`;
    }
    return `${indent}<${type}>`;
  }

  const props = [];
  for (const [key, value] of Object.entries(node)) {
    if (!verbose && key.startsWith('_')) continue;
    if (!showLoc && (key === 'location' || key.endsWith('Loc'))) continue;
    if (value === null || value === undefined) continue;

    const formatted = formatPrismNode(value, indent + '  ', options, seen);
    if (formatted.includes('\n')) {
      props.push(`${indent}  ${key}:\n${formatted}`);
    } else {
      props.push(`${indent}  ${key}: ${formatted.trim()}`);
    }
  }

  if (props.length === 0) return `${indent}(${type})`;
  return `${indent}(${type}\n${props.join('\n')}\n${indent})`;
}

function inspectPrismNode(node) {
  if (!node || typeof node !== 'object') {
    return `Value: ${JSON.stringify(node)} (${typeof node})`;
  }

  const type = node.constructor?.name || 'Object';
  const lines = [`Node Type: ${type}`, ''];

  const allProps = Object.getOwnPropertyNames(node);
  lines.push('Own Properties:');

  for (const key of allProps.sort()) {
    const value = node[key];
    let valueType;
    if (value === null) valueType = 'null';
    else if (value === undefined) valueType = 'undefined';
    else if (Array.isArray(value)) valueType = `Array[${value.length}]`;
    else if (typeof value === 'object') valueType = value.constructor?.name || 'Object';
    else valueType = typeof value;

    let preview;
    if (typeof value === 'string') preview = `"${value.slice(0, 50)}"`;
    else if (typeof value === 'boolean' || typeof value === 'number') preview = String(value);
    else preview = valueType;

    lines.push(`  ${key}: ${preview} (${valueType})`);
  }

  return lines.join('\n');
}

function findPrismNodes(node, pattern, results = [], nodePath = 'root') {
  if (!node || typeof node !== 'object') return results;

  const type = node.constructor?.name || '';
  const regex = new RegExp(pattern, 'i');

  if (regex.test(type)) {
    results.push({ path: nodePath, type, node });
  }

  if (Array.isArray(node)) {
    node.forEach((child, i) => findPrismNodes(child, pattern, results, `${nodePath}[${i}]`));
  } else {
    for (const [key, value] of Object.entries(node)) {
      if (key.startsWith('_') || key === 'location') continue;
      if (value && typeof value === 'object') {
        findPrismNodes(value, pattern, results, `${nodePath}.${key}`);
      }
    }
  }

  return results;
}

function formatAst(node, indent = '') {
  if (node === null || node === undefined) return 'nil';
  if (typeof node !== 'object' || !node.type) return JSON.stringify(node);

  const type = node.type;
  const children = node.children || [];

  if (children.length === 0) return `s(:${type})`;

  const hasNodeChildren = children.some(c => c && typeof c === 'object' && c.type);

  if (!hasNodeChildren) {
    return `s(:${type}, ${children.map(c => JSON.stringify(c)).join(', ')})`;
  }

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
// Main CLI
// ============================================================================

async function main() {
  const args = process.argv.slice(2);
  let outputMode = 'js';
  const options = { eslevel: 2020 };
  let file = null;
  let inlineCode = null;
  let searchPattern = null;
  let inspectPath = null;
  let verbose = false;
  let showLoc = false;
  let showComments = false;
  const filterNames = [];

  // Parse arguments
  let i = 0;
  while (i < args.length) {
    const arg = args[i];

    if (arg === '--ast') {
      outputMode = 'walker-ast';
    } else if (arg === '--filtered-ast') {
      outputMode = 'filtered-ast';
    } else if (arg === '--prism-ast') {
      outputMode = 'prism-ast';
    } else if (arg === '--compare') {
      outputMode = 'compare';
    } else if (arg === '--js') {
      outputMode = 'js';
    } else if (arg === '-e') {
      i++;
      inlineCode = args[i];
    } else if (arg.startsWith('--eslevel=')) {
      options.eslevel = parseInt(arg.split('=')[1], 10);
    } else if (arg === '--es2015') {
      options.eslevel = 2015;
    } else if (arg === '--es2016') {
      options.eslevel = 2016;
    } else if (arg === '--es2017') {
      options.eslevel = 2017;
    } else if (arg === '--es2018') {
      options.eslevel = 2018;
    } else if (arg === '--es2019') {
      options.eslevel = 2019;
    } else if (arg === '--es2020') {
      options.eslevel = 2020;
    } else if (arg === '--es2021') {
      options.eslevel = 2021;
    } else if (arg === '--es2022') {
      options.eslevel = 2022;
    } else if (arg === '--identity') {
      options.comparison = 'identity';
    } else if (arg === '--equality') {
      options.comparison = 'equality';
    } else if (arg === '--underscored_private') {
      options.underscored_private = true;
    } else if (arg === '--strict') {
      options.strict = true;
    } else if (arg === '--nullish') {
      options.or = 'nullish';
    } else if (arg === '--filter') {
      i++;
      filterNames.push(args[i]);
    } else if (arg.startsWith('--filter=')) {
      filterNames.push(arg.split('=')[1]);
    } else if (arg === '--verbose' || arg === '-v') {
      verbose = true;
    } else if (arg === '--loc') {
      showLoc = true;
    } else if (arg === '--show-comments') {
      showComments = true;
    } else if (arg === '--find' || arg === '-f') {
      i++;
      searchPattern = args[i];
      outputMode = 'find';
    } else if (arg.startsWith('--find=')) {
      searchPattern = arg.split('=')[1];
      outputMode = 'find';
    } else if (arg === '--inspect') {
      i++;
      inspectPath = args[i] || 'root';
      outputMode = 'inspect';
    } else if (arg.startsWith('--inspect=')) {
      inspectPath = arg.split('=')[1];
      outputMode = 'inspect';
    } else if (arg === '--help' || arg === '-h') {
      console.log(`Ruby2JS CLI - converts Ruby to JavaScript

Usage:
  ruby2js [options] [file]
  ruby2js -e "puts 'hello'"
  echo "puts 'hello'" | ruby2js [options]

Output Modes:
  --js              Output JavaScript (default)
  --ast             Output AST (Parser-compatible s-expression format)
  --filtered-ast    Output AST after filters are applied
  --prism-ast       Output raw Prism AST (verbose object format)
  --compare         Compare JS CLI output with Ruby CLI output (requires ruby2js in PATH)
  --find=PATTERN    Find nodes matching PATTERN (regex) in Prism AST
  --inspect=PATH    Inspect node at PATH (e.g., "root.statements.body[0]")

Conversion Options:
  -e CODE           Evaluate inline Ruby code
  --eslevel=NNNN    Set ECMAScript level (default: 2020)
  --es2015 .. --es2022  Set ECMAScript level
  --identity        Use === for == comparisons
  --equality        Use == for == comparisons
  --underscored_private  Prefix private properties with underscore (@foo -> _foo)
  --strict          Add "use strict" to output
  --nullish         Use ?? for 'or' operator
  --filter NAME     Apply filter (can be repeated, e.g., --filter functions)

Debug Options:
  --verbose, -v     Show all AST properties including internal ones
  --loc             Show location information in AST output
  --show-comments   Show comments map after conversion
  --help, -h        Show this help

Examples:
  ruby2js -e "puts 'hello'"
  ruby2js --filter functions -e "arr.map(&:to_s)"
  ruby2js --es2022 -e "class Foo; @x = 1; end"
  ruby2js --ast -e "self.p ||= 1"
`);
      process.exit(0);
    } else if (!arg.startsWith('-')) {
      file = arg;
    }

    i++;
  }

  // Read source
  let source = null;
  if (inlineCode) {
    source = inlineCode;
  } else if (file) {
    source = fs.readFileSync(file, 'utf-8');
    options.file = file;
  } else if (process.stdin.isTTY) {
    console.error('Error: No input. Provide a file, use -e CODE, or pipe Ruby code via stdin.');
    console.error('Use --help for usage information.');
    process.exit(1);
  } else {
    source = fs.readFileSync(0, 'utf-8');
  }

  // Load filters dynamically
  const loadedFilters = [];
  if (filterNames.length > 0) {
    const scriptDir = path.dirname(fileURLToPath(import.meta.url));

    // Normalize name for comparison (remove underscores, slashes, lowercase)
    const normalize = s => s.toLowerCase().replace(/[_/]/g, '');

    for (const name of filterNames) {
      try {
        const filterPath = path.join(scriptDir, 'filters', `${name}.js`);
        await import(filterPath);  // This registers the filter via registerFilter()

        // Find the filter in Ruby2JS.Filter using normalized comparison
        // (handles rails/model -> Rails_Model, camelCase -> Camelcase, etc.)
        const availableFilters = Object.keys(Ruby2JS.Filter || {});
        const actualName = availableFilters.find(n => normalize(n) === normalize(name));

        if (!actualName) {
          throw new Error(`Filter '${name}' not found after loading (available: ${availableFilters.join(', ')})`);
        }
        loadedFilters.push(Ruby2JS.Filter[actualName]);
      } catch (e) {
        console.error(`Error loading filter '${name}': ${e.message}`);
        process.exit(1);
      }
    }
  }

  try {
    // Initialize Prism
    const prismParse = await initPrism();
    const parseResult = prismParse(source);

    if (parseResult.errors && parseResult.errors.length > 0) {
      console.error('Parse error:', parseResult.errors[0].message);
      process.exit(1);
    }

    switch (outputMode) {
      case 'prism-ast':
        console.log(formatPrismNode(parseResult.value, '', { verbose, showLoc }));
        break;

      case 'find': {
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
        break;
      }

      case 'inspect': {
        let node = parseResult.value;
        const parts = inspectPath.split(/\.|\[|\]/).filter(p => p !== '');
        if (parts[0] === 'root') parts.shift();

        for (const part of parts) {
          if (node === null || node === undefined) {
            console.error(`Path "${inspectPath}" not found (stopped at null/undefined)`);
            process.exit(1);
          }
          node = /^\d+$/.test(part) ? node[parseInt(part, 10)] : node[part];
        }

        console.log(`Inspecting: ${inspectPath}\n`);
        console.log(inspectPrismNode(node));
        break;
      }

      case 'walker-ast': {
        const walker = new Ruby2JS.PrismWalker(source, options.file);
        const ast = walker.visit(parseResult.value);
        console.log(formatAst(ast));
        break;
      }

      case 'filtered-ast': {
        // Get AST after filters are applied
        const walker = new Ruby2JS.PrismWalker(source, options.file);
        let ast = walker.visit(parseResult.value);

        if (loadedFilters.length > 0) {
          options.filters = loadedFilters;
        }

        // Use Pipeline to apply filters
        const sourceBuffer = walker.source_buffer;
        const wrappedComments = (parseResult.comments || []).map(c =>
          new PrismComment(c, source, sourceBuffer)
        );
        const comments = associateComments(ast, wrappedComments);

        const pipeline = new Ruby2JS.Pipeline(ast, comments, {
          filters: loadedFilters,
          options: { ...options, source }
        });

        // Access the filtered AST (pipeline.run applies filters before conversion)
        // We need to apply filters without running the converter
        if (loadedFilters.length > 0) {
          pipeline.apply_filters;
        }
        console.log(formatAst(pipeline._ast));
        break;
      }

      case 'compare': {
        // Compare JS CLI output with Ruby CLI output
        const { execSync } = await import('child_process');
        const scriptDir = path.dirname(fileURLToPath(import.meta.url));
        const rubyCliPath = path.join(scriptDir, '../../bin/ruby2js');

        // Build Ruby CLI args
        const rubyArgs = [];
        if (options.eslevel) rubyArgs.push(`--es${options.eslevel}`);
        if (options.comparison === 'identity') rubyArgs.push('--identity');
        if (options.comparison === 'equality') rubyArgs.push('--equality');
        for (const name of filterNames) rubyArgs.push('--filter', name);

        // Get Ruby CLI output
        let rubyOutput;
        try {
          rubyOutput = execSync(`${rubyCliPath} ${rubyArgs.join(' ')} -e '${source.replace(/'/g, "'\\''")}'`, {
            encoding: 'utf-8',
            cwd: scriptDir
          }).trim();
        } catch (e) {
          rubyOutput = `[Ruby CLI Error: ${e.message}]`;
        }

        // Get JS CLI output
        let jsOutput;
        try {
          if (loadedFilters.length > 0) {
            options.filters = loadedFilters;
          }
          jsOutput = convert(source, { ...options, filters: loadedFilters }).toString().trim();
        } catch (e) {
          jsOutput = `[JS CLI Error: ${e.message}]`;
        }

        // Compare
        console.log('=== Ruby CLI ===');
        console.log(rubyOutput);
        console.log('\n=== JS CLI ===');
        console.log(jsOutput);
        console.log('\n=== Match ===');
        console.log(rubyOutput === jsOutput ? '✓ Output matches' : '✗ Output differs');

        if (rubyOutput !== jsOutput) {
          // Show character-level diff hint
          const minLen = Math.min(rubyOutput.length, jsOutput.length);
          for (let i = 0; i < minLen; i++) {
            if (rubyOutput[i] !== jsOutput[i]) {
              console.log(`  First difference at position ${i}: Ruby='${rubyOutput.slice(i, i+20)}...' JS='${jsOutput.slice(i, i+20)}...'`);
              break;
            }
          }
          if (rubyOutput.length !== jsOutput.length) {
            console.log(`  Length: Ruby=${rubyOutput.length}, JS=${jsOutput.length}`);
          }
        }
        break;
      }

      default: {
        // JavaScript output - use convert() with filters (same pipeline as build scripts)
        const result = convert(source, { ...options, filters: loadedFilters });

        if (showComments) {
          console.log('=== Comments Map ===');
          // Access comments from the converter's class variable
          const commentsMap = Ruby2JS.Converter.last_comments;
          if (commentsMap && commentsMap.size > 0) {
            let hasEntries = false;
            commentsMap.forEach((value, key) => {
              if (key === '_raw' || !value || value.length === 0) return;
              hasEntries = true;
              const nodeDesc = (key && key.type) ? `s(:${key.type}, ...)` : String(key).slice(0, 50);
              console.log(`  ${nodeDesc}`);
              value.forEach(c => console.log(`    => ${JSON.stringify(c.text || c)}`));
            });
            if (!hasEntries) console.log('(all comments empty)');
          } else {
            console.log('(no comments)');
          }
          console.log('');
          console.log('=== JavaScript Output ===');
        }

        console.log(result.toString());
      }
    }
  } catch (e) {
    console.error('Error:', e.message);
    if (process.env.DEBUG) console.error(e.stack);
    process.exit(1);
  }
}

main();
