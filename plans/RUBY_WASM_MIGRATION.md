# ruby.wasm Migration Plan

## Overview

Replace Opal with [ruby.wasm](https://github.com/ruby/ruby.wasm) for the online demo at ruby2js.com. This enables Ruby 4.0 syntax support (via Prism) while reducing bundle size.

**Why now:** The whitequark `parser` gem only supports Ruby 3.3 and lower. Ruby 4.0 releases December 2024. Opal cannot use Prism (written in C).

**Related:** See [PRISM_MIGRATION.md](./PRISM_MIGRATION.md) and [SELF_HOSTING.md](./SELF_HOSTING.md) for context.

## Current Architecture (Opal)

```
demo/ruby2js.opal
       ↓
Opal compiler (opal --compile)
       ↓
ruby2js.js (~5.4MB minified)
       ↓
Browser loads JS, runs Ruby2JS via Opal runtime
```

**Files involved:**
- `demo/ruby2js.opal` - Main entry point, JavaScript interop
- `demo/patch.opal` - Patches to Parser gem for Opal compatibility
- `demo/filters.opal` - Auto-generated filter imports (via Rake)
- `lib/ruby2js/**/*.rb` - Core Ruby2JS code (compiled via Opal)
- `docs/Rakefile` - Build task using `opal --compile`

**Issues:**
- Parser gem doesn't support Ruby 4.0 syntax
- 5.4MB bundle size (minified)
- Many Opal-specific patches required (`patch.opal`)
- Opal runtime overhead

## Proposed Architecture (ruby.wasm)

```
@ruby/wasm-wasi npm package (CDN)
       ↓
CRuby + Prism (WebAssembly)
       ↓
Browser loads WASM, runs real Ruby with Prism parser
       ↓
Ruby2JS gem (bundled into WASM or loaded from virtual FS)
       ↓
<script type="text/ruby"> runs demo logic directly
```

**Benefits:**
- Full Ruby 3.4/4.0 compatibility including Prism
- No Opal patches needed
- Real CRuby behavior
- Actively maintained by Ruby core team
- Demo logic runs as Ruby, not transpiled JS

## Implementation Phases

### Phase 1: Proof of Concept

**Goal:** Get Ruby2JS running in browser via ruby.wasm

1. Create test HTML page loading ruby.wasm from CDN:
   ```html
   <script src="https://cdn.jsdelivr.net/npm/@ruby/3.4-wasm-wasi@2.7.2/dist/browser.script.iife.js"></script>
   <script type="text/ruby">
     require "ruby2js"
     result = Ruby2JS.convert('puts "hello"')
     JS.global[:document].write(result.to_s)
   </script>
   ```
2. Determine how to make Ruby2JS available to ruby.wasm (bundle vs virtual FS)
3. Test basic conversion and measure load time

**Success criteria:** `Ruby2JS.convert('puts "hello"')` returns `console.log("hello")` in browser

**Estimated effort:** 2-3 days

### Phase 2: Replace Opal Demo with ruby.wasm

**Goal:** Working demo using ruby.wasm instead of Opal

**Tasks:**
1. Build custom ruby.wasm with Ruby2JS and filters using `rbwasm` CLI:
   ```bash
   rbwasm build --ruby-version 3.4 -o ruby2js.wasm -- \
     -r ruby2js -r ruby2js/filter/functions -r ruby2js/filter/esm ...
   ```
2. Update demo HTML to load ruby.wasm instead of Opal bundle
3. Rewrite `demo/ruby2js.opal` as plain Ruby for ruby.wasm
4. Add loading indicator (WASM initialization takes time)
5. Test all demo features work (editor, filters, options, AST display)
6. Update `docs/Rakefile` build tasks

**Estimated effort:** 5-7 days

### Phase 3: Cleanup

**Goal:** Remove Opal dependencies

**Tasks:**
1. Remove Opal-specific files (`demo/ruby2js.opal`, `demo/patch.opal`, `demo/filters.opal`)
2. Update `docs/Gemfile` - remove Opal dependency
3. Document new architecture

**Estimated effort:** 1-2 days

## Total Estimated Effort: 8-12 days

## Technical Considerations

### File System Access

ruby.wasm uses a virtual file system. Ruby2JS source files must be:
- Bundled into the WASM binary, OR
- Loaded via HTTP and mounted to virtual FS

```javascript
// Example: mounting files to virtual filesystem
const ruby = await loadRuby();
ruby.mount('/ruby2js', await fetchRuby2JSSources());
```

### Filter Loading

Current Opal demo pre-compiles all filters. With ruby.wasm we can:
1. Bundle all filters (larger WASM, faster runtime)
2. Load filters on-demand (smaller initial load, slower filter switching)
3. Hybrid: bundle common filters, lazy-load others

### Prism vs Parser Gem

With ruby.wasm, Ruby2JS will use Prism automatically on Ruby 3.3+. The existing `RUBY2JS_PARSER` environment variable logic should work:

```ruby
# lib/ruby2js.rb already handles this
if prism_available?
  require 'prism'
  # Use Prism::Translation::Parser
else
  require 'parser/current'
end
```

### Memory Usage

ruby.wasm runs in WebAssembly linear memory. Monitor for:
- Memory growth with large source files
- Memory leaks from repeated conversions
- Browser tab memory limits (~2-4GB)

### Browser Compatibility

ruby.wasm requires:
- WebAssembly support (all modern browsers)
- WASI shim (provided by @aspect/ruby-wasm)

Minimum versions:
- Chrome 57+
- Firefox 52+
- Safari 11+
- Edge 16+

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| ruby.wasm doesn't support required Ruby feature | High | Test thoroughly in Phase 1; fall back to Option B (custom build) |
| Performance too slow | Medium | Implement caching, lazy loading; consider self-hosting long-term |
| WASM binary too large | Medium | Use streaming compilation; implement Service Worker caching |
| Breaking changes in ruby.wasm | Medium | Pin to specific version; monitor releases |
| Browser compatibility issues | Low | Test across browsers; provide fallback message |

## Alternatives Considered

### Keep Opal (Not Recommended)

- Parser gem won't support Ruby 4.0
- Would require forking/maintaining parser gem
- Accumulating technical debt

### Self-Hosting (Future Consideration)

Transpile Ruby2JS itself to JavaScript (see [SELF_HOSTING.md](./SELF_HOSTING.md)).

- Smallest possible bundle (~1MB)
- Highest complexity
- Consider after ruby.wasm migration if bundle size is critical

### Server-Side Conversion

Run Ruby2JS on server, send results to browser.

- Adds server dependency
- Latency for each conversion
- Doesn't work offline
- Not recommended for interactive demo

## Success Criteria

- [ ] Demo works with Ruby 3.4 syntax
- [ ] Demo works with Ruby 4.0 syntax (when released)
- [ ] Load time < 5 seconds on broadband
- [ ] All existing demo features work
- [ ] No Opal dependencies remain
- [ ] Documented for future maintainers

## References

- [ruby.wasm GitHub](https://github.com/ruby/ruby.wasm)
- [@ruby/3.4-wasm-wasi npm](https://www.npmjs.com/package/@ruby/3.4-wasm-wasi)
- [ruby.wasm browser examples](https://github.com/aspect-js/aspect/tree/main/packages/aspect-runtime/examples)
- [First steps with ruby.wasm - Evil Martians](https://evilmartians.com/chronicles/first-steps-with-ruby-wasm-or-building-ruby-next-playground)
- [whitequark/parser deprecation notice](https://github.com/whitequark/parser)
- [Prism documentation](https://ruby.github.io/prism/)
