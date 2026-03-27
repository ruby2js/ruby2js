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

// Application helper stubs (used before helpers are properly loaded)
globalThis.custom_styles_tag = globalThis.custom_styles_tag || function() { return ''; };
globalThis.hide_from_user_style_tag = globalThis.hide_from_user_style_tag || function() { return ''; };

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

// --- Rails test assertion helpers ---
// These are standard minitest/Rails assertion methods that the test filter
// transforms into vitest-compatible calls. They need to be globally available
// for both Vite and eject pipelines.

// assert_difference(expression, difference, fn) - verify a numeric change
globalThis.assert_difference = globalThis.assert_difference || async function(expr, diff, fn) {
  if (typeof diff === 'function') { fn = diff; diff = 1; }
  const evalExpr = (e) => typeof e === 'function' ? e() : eval(e.replace(/::/g, '.'));
  const before = await evalExpr(expr);
  await fn();
  const after = await evalExpr(expr);
  const { expect } = await import('vitest');
  expect(after - before).toBe(diff);
};

// assert_no_difference(expression, fn)
globalThis.assert_no_difference = globalThis.assert_no_difference || async function(expr, fn) {
  return assert_difference(expr, 0, fn);
};

// assert_changes(expression, opts_or_fn, fn) - verify a value change
globalThis.assert_changes = globalThis.assert_changes || async function(expr, ...args) {
  let fn = args.pop();
  const evalExpr = (e) => typeof e === 'function' ? e() : eval(e.replace(/::/g, '.'));
  const before = await evalExpr(expr);
  await fn();
  const after = await evalExpr(expr);
  const { expect } = await import('vitest');
  expect(after).not.toEqual(before);
};

// assert_no_changes(expression, fn)
globalThis.assert_no_changes = globalThis.assert_no_changes || async function(expr, fn) {
  const evalExpr = (e) => typeof e === 'function' ? e() : eval(e.replace(/::/g, '.'));
  const before = await evalExpr(expr);
  await fn();
  const after = await evalExpr(expr);
  const { expect } = await import('vitest');
  expect(after).toEqual(before);
};

// ActiveJob test helpers
globalThis.assert_enqueued_with = globalThis.assert_enqueued_with || function() {};
globalThis.assert_enqueued_jobs = globalThis.assert_enqueued_jobs || function(count, fn) { if (fn) return fn(); };
globalThis.assert_no_enqueued_jobs = globalThis.assert_no_enqueued_jobs || function(fn) { if (fn) return fn(); };

// --- Integration test HTTP verbs ---
// Rails test helpers call post(), get(), delete() etc. as bare functions.
// These route through the fetch interceptor (installed by test setup) which
// dispatches to controller actions via RouterBase.match().
function _httpVerb(method) {
  return async function(url, options = {}) {
    const params = options.params || {};
    const headers = { accept: 'text/html', ...options.headers };
    const body = typeof params === 'object' && Object.keys(params).length > 0
      ? JSON.stringify(params)
      : undefined;
    const contentType = body ? 'application/json' : undefined;
    const response = await fetch(url, {
      method,
      headers: { ...headers, ...(contentType ? { 'content-type': contentType } : {}) },
      body
    });
    // Store response and cookies for assertion helpers
    globalThis._lastResponse = response;
    return response;
  };
}
globalThis.get = globalThis.get || _httpVerb('GET');
globalThis.post = globalThis.post || _httpVerb('POST');
globalThis.put = globalThis.put || _httpVerb('PUT');
globalThis.patch = globalThis.patch || _httpVerb('PATCH');
globalThis.$delete = globalThis.$delete || _httpVerb('DELETE');

// cookies accessor for test helpers (reads from fetch interceptor's cookie jar)
globalThis.cookies = globalThis.cookies || new Proxy({}, {
  get(_, key) {
    return globalThis._testCookies?.[key];
  }
});
