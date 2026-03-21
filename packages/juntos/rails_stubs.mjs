// Runtime stubs for Rails DSL methods called on concern factory functions.
// Concern factories are arrow functions, not classes, so they don't inherit
// static methods from ApplicationRecord. These stubs ensure DSL calls like
// Leafable.delegate(...) don't crash at module evaluation time.
//
// For regular model classes, the real implementations on ApplicationRecord
// take precedence (prototype chain lookup finds the class method first).

Function.prototype.delegate = Function.prototype.delegate || function() {};
Function.prototype.validates = Function.prototype.validates || function() {};
Function.prototype.validate = Function.prototype.validate || function() {};
Function.prototype.has_markdown = Function.prototype.has_markdown || function() {};

// Controller concern inclusion (no-op for MVP — concerns not mixed into controller IIFEs)
globalThis.include = globalThis.include || function() {};

// Authentication stubs (Rails 8 generated authentication concern)
globalThis.allow_unauthenticated_access = globalThis.allow_unauthenticated_access || function() {};
globalThis.signed_in = true;  // Default to authenticated for MVP
globalThis.require_authentication = globalThis.require_authentication || function() {};
Function.prototype.has_one_attached = Function.prototype.has_one_attached || function() {};
Function.prototype.has_many_attached = Function.prototype.has_many_attached || function() {};
Function.prototype.has_rich_text = Function.prototype.has_rich_text || function() {};
Function.prototype.positioned_within = Function.prototype.positioned_within || function() {};
Function.prototype.cattr_accessor = Function.prototype.cattr_accessor || function(name, defaultFn) {
  // Class-level attribute with optional default
  const key = `_${name}`;
  Object.defineProperty(this, name, {
    get() { return this[key] ?? (defaultFn ? defaultFn() : undefined); },
    set(v) { this[key] = v; },
    configurable: true
  });
};
