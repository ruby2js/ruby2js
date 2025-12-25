---
order: 24
title: Polyfill
top_section: Filters
category: polyfill
---

The **Polyfill** filter adds JavaScript prototype polyfills for Ruby methods that don't have direct JavaScript equivalents. Unlike the [Functions filter](/docs/filters/functions) which transforms method calls inline (e.g., `.first` becomes `[0]`), the Polyfill filter preserves the Ruby method names and adds runtime polyfill definitions at the top of your output.

This is useful when you want to:
- Keep Ruby-style method names in your JavaScript for readability
- Use methods like `first` and `last` as property accessors (without parentheses)

{% rendercontent "docs/note", title: "Filter Ordering" %}
The Polyfill filter automatically reorders itself to run before the Functions filter. This ensures that polyfilled methods aren't transformed by the Functions filter.
{% endrendercontent %}

## Supported Methods

### Array Methods

| Ruby | JavaScript Polyfill |
|------|---------------------|
| `.first` | Property getter returning `this[0]` |
| `.last` | Property getter returning `this.at(-1)` |
| `.compact` | Property getter returning new array without `null`/`undefined` |
| `.uniq` | Property getter returning `[...new Set(this)]` (duplicates removed) |
| `.rindex { }` | Method that finds last index matching block |
| `.insert(i, items)` | Method using `splice` to insert items |
| `.delete_at(i)` | Method using `splice` to remove item at index |

### String Methods

| Ruby | JavaScript Polyfill |
|------|---------------------|
| `.chomp(suffix)` | Removes suffix (or `\r?\n` if no arg) from end |
| `.delete_prefix(prefix)` | Removes prefix from start if present |
| `.delete_suffix(suffix)` | Removes suffix from end if present |
| `.count(chars)` | Counts occurrences of any character in `chars` |

### Object Methods

| Ruby | JavaScript Polyfill |
|------|---------------------|
| `.to_a` | Property getter returning `Object.entries(this)` |

### RegExp Methods

| Ruby | JavaScript Polyfill |
|------|---------------------|
| `Regexp.escape(str)` | `RegExp.escape(str)` with polyfill for pre-ES2025 |

{% rendercontent "docs/note", title: "ES2025 Native Support" %}
`RegExp.escape` is a native JavaScript method in ES2025+. The polyfill is only added for earlier ES levels.
{% endrendercontent %}

## Examples

```ruby
# Input
arr.first
arr.last
arr.compact
arr.uniq
str.chomp("\n")
hash.to_a
```

```javascript
// Output (polyfills prepended, then code)
Object.defineProperty(Array.prototype, "first", {
  get() { return this[0] },
  configurable: true
});

Object.defineProperty(Array.prototype, "last", {
  get() { return this.at(-1) },
  configurable: true
});

Object.defineProperty(Array.prototype, "compact", {
  get() { return this.filter(x => x !== null && x !== undefined) },
  configurable: true
});

Object.defineProperty(Array.prototype, "uniq", {
  get() { return [...new Set(this)] },
  configurable: true
});

if (!String.prototype.chomp) {
  String.prototype.chomp = function(suffix) {
    if (suffix === undefined) return this.replace(/\r?\n$/m, "");
    if (this.endsWith(suffix)) return this.slice(0, this.length - suffix.length);
    return String(this)
  }
}

Object.defineProperty(Object.prototype, "to_a", {
  get() { return Object.entries(this) },
  configurable: true
});

arr.first;
arr.last;
arr.compact;
arr.uniq;
str.chomp("\n");
hash.to_a
```

## Polyfill vs Functions Filter

The key difference between Polyfill and Functions:

| Method | Polyfill Filter | Functions Filter |
|--------|-----------------|------------------|
| `arr.first` | `arr.first` (property) | `arr[0]` |
| `arr.last` | `arr.last` (property) | `arr[arr.length - 1]` |
| `arr.compact` | `arr.compact` (property) | `arr.filter(x => x != null)` |
| `arr.uniq` | `arr.uniq` (property) | `[...new Set(arr)]` |
| `str.chomp` | `str.chomp()` (method) | `str.replace(/\r?\n$/, "")` |

Choose **Polyfill** when you want Ruby-style method names preserved in the output. Choose **Functions** when you want zero-runtime-overhead inline transformations.

{% rendercontent "docs/note", extra_margin: true %}
More examples of how this filter works are in the [specs file](https://github.com/ruby2js/ruby2js/blob/master/spec/polyfill_spec.rb).
{% endrendercontent %}
