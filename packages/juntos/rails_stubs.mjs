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

// tag helper (Rails ActionView::Helpers::TagHelper)
// Generates HTML tags: tag.style("css") → <style>css</style>
globalThis.tag = globalThis.tag || new Proxy({}, {
  get(_, name) {
    return (content, attrs = {}) => {
      const attrStr = Object.entries(attrs).map(([k, v]) =>
        typeof v === 'object' ? Object.entries(v).map(([k2, v2]) => ` data-${k2}="${v2}"`).join('') : ` ${k}="${v}"`
      ).join('');
      return `<${name}${attrStr}>${content}</${name}>`;
    };
  }
});

// Controller concern inclusion (no-op for MVP — concerns not mixed into controller IIFEs)
globalThis.include = globalThis.include || function() {};

// html_safe — no-op in JS (all strings are safe, escaping handled by escapeHTML)
String.prototype.html_safe = String.prototype.html_safe || function() { return this.toString(); };

// Fragment caching — pass-through for MVP (executes block without caching)
// Returns the promise so the ERB template can await it.
// The callback mutates _buf as a side effect.
globalThis.cache = globalThis.cache || function(key, fn) { return fn(); };

// Authentication stubs (Rails 8 generated authentication concern)
globalThis.allow_unauthenticated_access = globalThis.allow_unauthenticated_access || function() {};
globalThis.signed_in = false;  // Default to not authenticated
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
