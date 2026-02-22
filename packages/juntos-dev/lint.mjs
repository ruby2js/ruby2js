/**
 * Structural anti-pattern checker for Ruby→JS transpilation.
 *
 * Walks the raw AST (before filters) to detect patterns documented in
 * docs/src/_docs/users-guide/anti-patterns.md that will fail or produce
 * incorrect JavaScript output.
 *
 * Used by lintRuby() in transform.mjs.
 */

/**
 * Walk an AST node tree and collect structural diagnostics.
 *
 * @param {Object} node - AST node (from ruby2js parse)
 * @param {Array} diagnostics - Mutable array to push diagnostics into
 * @param {string} filePath - Source file path for diagnostic messages
 */
export function checkStructural(node, filePath) {
  const diagnostics = [];
  walkNode(node, diagnostics, filePath);
  return diagnostics;
}

function nodeLocation(node) {
  if (!node) return { line: null, column: null };

  const loc = node.loc || node.location;
  if (!loc) return { line: null, column: null };

  // Ruby AST style: loc.expression
  if (loc.expression) {
    return {
      line: loc.expression.line,
      column: loc.expression.column
    };
  }

  // Direct line property
  if (loc.line != null) {
    return { line: loc.line, column: loc.column };
  }

  // Hash-style location from Prism
  if (loc.start_line != null) {
    return { line: loc.start_line, column: loc.start_column };
  }

  return { line: null, column: null };
}

function pushDiag(diagnostics, node, filePath, severity, rule, message) {
  const { line, column } = nodeLocation(node);
  diagnostics.push({ severity, rule, message, file: filePath, line, column });
}

function walkNode(node, diagnostics, filePath) {
  if (!node || typeof node !== 'object') return;

  // Handle array of nodes (e.g., body of a begin/class)
  if (Array.isArray(node)) {
    for (const child of node) {
      walkNode(child, diagnostics, filePath);
    }
    return;
  }

  const type = node.type;
  if (!type) return;

  const children = node.children || [];

  switch (type) {
    case 'def': {
      const methodName = children[0];

      // method_missing is not transpilable
      if (methodName === 'method_missing') {
        pushDiag(diagnostics, node, filePath, 'error', 'method_missing',
          "method_missing cannot be transpiled to JavaScript");
      }

      // Operator method definitions — JS has no operator overloading
      if (/^(<=>|<<?|>>?|<=>|[+\-*\/%&|^~]=?|={2,3}|!={0,2}|\[\]=?|[<>]=?|\*\*)$/.test(methodName)) {
        pushDiag(diagnostics, node, filePath, 'error', 'operator_method',
          `operator method 'def ${methodName}' cannot be transpiled — JavaScript has no operator overloading`);
      }
      break;
    }

    case 'defs': {
      // Singleton methods: def self.method inside a class transpiles cleanly
      // to static methods. Only warn for non-self receivers (def obj.method).
      const defReceiver = children[0];
      if (!defReceiver || defReceiver.type !== 'self') {
        pushDiag(diagnostics, node, filePath, 'warning', 'singleton_method',
          "singleton method definition (def obj.method) has limited JavaScript support");
      }
      break;
    }

    case 'send': {
      const receiver = children[0];
      const method = children[1];

      // eval() call
      if (receiver === null && method === 'eval') {
        pushDiag(diagnostics, node, filePath, 'error', 'eval_call',
          "eval() cannot be safely transpiled to JavaScript");
      }

      // instance_eval
      if (method === 'instance_eval') {
        pushDiag(diagnostics, node, filePath, 'error', 'instance_eval',
          "instance_eval cannot be transpiled to JavaScript");
      }

      // Ruby catch/throw (not JS try/catch)
      if (receiver === null && (method === 'catch' || method === 'throw')) {
        pushDiag(diagnostics, node, filePath, 'warning', 'ruby_catch_throw',
          `Ruby '${method}' has different semantics than JavaScript '${method}'`);
      }

      // prepend
      if (method === 'prepend') {
        pushDiag(diagnostics, node, filePath, 'warning', 'prepend_call',
          "prepend has no JavaScript equivalent");
      }

      // force_encoding
      if (method === 'force_encoding') {
        pushDiag(diagnostics, node, filePath, 'warning', 'force_encoding',
          "force_encoding has no JavaScript equivalent (JS strings are always UTF-16)");
      }
      break;
    }

    case 'retry': {
      pushDiag(diagnostics, node, filePath, 'warning', 'retry_statement',
        "retry has no direct JavaScript equivalent");
      break;
    }

    case 'redo': {
      pushDiag(diagnostics, node, filePath, 'warning', 'redo_statement',
        "redo has no direct JavaScript equivalent");
      break;
    }
  }

  // Recurse into children
  for (const child of children) {
    if (child && typeof child === 'object') {
      walkNode(child, diagnostics, filePath);
    }
  }
}
