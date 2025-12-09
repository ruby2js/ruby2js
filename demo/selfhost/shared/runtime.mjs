// Shared runtime classes for selfhosted Ruby2JS
// These provide Parser-compatible source location tracking for the JS environment.
//
// Note: These classes differ from their Ruby equivalents (in lib/ruby2js.rb)
// because JavaScript doesn't need the hash/equality methods Ruby uses for
// comment association. The JS implementation uses simpler approaches.

import * as Prism from '@ruby/prism';

// Set up Prism global before other modules that extend Prism.Visitor
export { Prism };

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
