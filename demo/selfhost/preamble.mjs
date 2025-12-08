// Preamble: Ruby built-ins needed by the transpiled converter
// These are Ruby classes/modules that don't exist in JavaScript

// NotImplementedError - Ruby's built-in exception for unimplemented methods
export class NotImplementedError extends Error {
  constructor(message) {
    super(message);
    this.name = 'NotImplementedError';
  }
}

// Set class is built into JS, but Ruby's Set has some different methods
// The transpiled code uses Set.new which becomes new Set() automatically

// Make available globally for the converter module
globalThis.NotImplementedError = NotImplementedError;
