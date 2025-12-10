// Shared runtime classes for selfhosted Ruby2JS
// These provide Parser-compatible source location tracking for the JS environment.
//
// Note: These classes differ from their Ruby equivalents (in lib/ruby2js.rb)
// because JavaScript doesn't need the hash/equality methods Ruby uses for
// comment association. The JS implementation uses simpler approaches.
//
// This module can be used in two ways:
// 1. Node.js CLI: imports @ruby/prism directly
// 2. Browser: imports prism_browser.mjs wrapper (handles WASM loading)
//
// The Prism import is at the top; browser builds should replace this import.

import * as Prism from '@ruby/prism';

// Re-export Prism for consumers
export { Prism };

// ============================================================================
// Source Location Classes (Prism-independent)
// ============================================================================

// PrismSourceBuffer - provides source buffer for location tracking
export class PrismSourceBuffer {
  constructor(source, file) {
    this.source = source;
    this.name = file || '(eval)';
    // Build line offsets for line/column calculation
    this._lineOffsets = [0];
    for (let i = 0; i < source.length; i++) {
      if (source[i] === '\n') {
        this._lineOffsets.push(i + 1);
      }
    }
  }

  lineForPosition(pos) {
    let idx = this._lineOffsets.findIndex(offset => offset > pos);
    return idx === -1 ? this._lineOffsets.length : idx;
  }

  columnForPosition(pos) {
    let lineIdx = this._lineOffsets.findIndex(offset => offset > pos);
    if (lineIdx === -1) lineIdx = this._lineOffsets.length;
    return pos - this._lineOffsets[lineIdx - 1];
  }
}

// PrismSourceRange - provides source range for location tracking
export class PrismSourceRange {
  constructor(sourceBuffer, beginPos, endPos) {
    this.source_buffer = sourceBuffer;
    this.begin_pos = beginPos;
    this.end_pos = endPos;
  }

  get source() {
    return this.source_buffer.source.slice(this.begin_pos, this.end_pos);
  }

  get line() {
    return this.source_buffer.lineForPosition(this.begin_pos);
  }

  get column() {
    return this.source_buffer.columnForPosition(this.begin_pos);
  }
}

// Hash class placeholder - used for instanceof checks
// Ruby Hash === x patterns have been changed to x.is_a?(Hash)
export class Hash {}

// ============================================================================
// Comment Handling
// ============================================================================

// PrismComment wrapper - provides interface expected by converter
export class PrismComment {
  constructor(prismComment, source, sourceBuffer) {
    const start = prismComment.location.startOffset;
    const end = start + prismComment.location.length;
    this.text = source.slice(start, end);

    this.location = {
      startOffset: start,
      endOffset: end,
      end_offset: end
    };

    this.loc = {
      start_offset: start,
      expression: {
        source_buffer: sourceBuffer,
        begin_pos: start,
        end_pos: end
      }
    };
  }
}

// CommentsMap - alias for Map (object key support)
export const CommentsMap = Map;

// Associate comments with AST nodes based on position
// Transpiled from lib/ruby2js.rb Ruby2JS.associate_comments using:
//   bin/ruby2js --include call --filter functions
// Note: Ruby uses `child.respond_to?(:type) && child.respond_to?(:children)`
// but the transpilable source uses `child&.type` which becomes `child?.type` in JS.
// Both are semantically equivalent for AST traversal.
export function associateComments(ast, comments) {
  let result = new CommentsMap();
  if (comments == null || comments.length == 0 || ast == null) return result;
  let nodes_by_pos = [];

  let collect_nodes = (node, depth) => {
    if (!node || !node.loc) return;
    let start_pos = node.loc.start_offset;

    if (start_pos && node.type != "begin") {
      nodes_by_pos.push([start_pos, depth, node])
    }

    if (node.children) {
      for (let child of node.children) {
        if (child?.type) collect_nodes(child, depth + 1)
      }
    }
  };

  collect_nodes(ast, 0);

  nodes_by_pos.sort((a, b) => {
    let cmp = a[0] - b[0];
    return cmp != 0 ? cmp : a[1] - b[1]
  });

  for (let comment of comments) {
    let comment_end = comment.location.end_offset;
    let candidate = nodes_by_pos.find(item => item[0] >= comment_end);
    if (!candidate) continue;
    let node = candidate[2];
    if (!result.has(node)) result.set(node, []);
    result.get(node).push(comment)
  }

  return result
}

// Set up globals for modules that expect them
export function setupGlobals() {
  globalThis.Prism = Prism;
  globalThis.PrismSourceBuffer = PrismSourceBuffer;
  globalThis.PrismSourceRange = PrismSourceRange;
  globalThis.Hash = Hash;
  globalThis.RUBY_VERSION = "3.4.0";
  globalThis.RUBY2JS_PARSER = "prism";
}

// Initialize Prism WASM parser
let prismParse = null;

export async function initPrism() {
  if (!prismParse) {
    prismParse = await Prism.loadPrism();
  }
  return prismParse;
}

export function getPrismParse() {
  return prismParse;
}
