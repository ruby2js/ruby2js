# ruby.wasm Migration Plan

## Overview

Replace Opal with [ruby.wasm](https://github.com/ruby/ruby.wasm) for the online demo at ruby2js.com. This enables Ruby 4.0 syntax support (via Prism) while reducing bundle size.

**Why now:** The whitequark `parser` gem only supports Ruby 3.3 and lower. Ruby 4.0 releases December 2025. Opal cannot use Prism (written in C).

**Related:** See [PRISM_MIGRATION.md](./PRISM_MIGRATION.md) and [SELF_HOSTING.md](./SELF_HOSTING.md) for context.

## Phase 1: Proof of Concept - COMPLETE

**Status:** Successfully demonstrated Ruby2JS running with Ruby 4.0 + Prism in browser.

**Results:**
- Ruby 4.0.0dev with Prism 1.6.0 working
- 41MB WASM (vs 63MB for full build, vs 5.4MB Opal)
- 0.37s total load time in browser
- All basic conversions working with Prism parser

**Approach that worked:**
1. Use pre-built Ruby WASM from npm (`@ruby/head-wasm-wasi` for 4.0, will be `@ruby/4.0-wasm-wasi` after release)
2. Pack gems on top using `rbwasm pack`
3. Monkey-patch `require` and `require_relative` to work around WASI VFS `realpath_rec` limitation

**Build process:**
```bash
# Download pre-built Ruby 4.0 WASM from npm
npm pack @ruby/head-wasm-wasi@latest
tar -xzf ruby-head-wasm-wasi-*.tgz package/dist/ruby+stdlib.wasm
mv package/dist/ruby+stdlib.wasm ruby-head.wasm

# Pack gems on top (ast, racc, parser, ruby2js)
rbwasm pack ruby-head.wasm \
  --dir /path/to/ast/lib::/gems/ast/lib \
  --dir /path/to/racc/lib::/gems/racc/lib \
  --dir /path/to/parser/lib::/gems/parser/lib \
  --dir /path/to/ruby2js/lib::/gems/ruby2js \
  -o ruby2js-4.0.wasm
```

**Key technical findings:**
- `rbwasm build` compiles Ruby from source (~5 min) but produces WASM without legacy ABI
- `rbwasm pack` is fast but has `realpath_rec` issues with WASI VFS
- Pre-built npm WASMs have correct ABI and work with `@ruby/wasm-wasi` JS library
- Need to monkey-patch `require`/`require_relative` to bypass realpath issues
- Must pack all dependencies: ruby2js, parser, racc, ast

**PoC files created:**
- `demo/wasm/poc-ruby4.html` - Browser demo
- `demo/wasm/poc-ruby4.cjs` - Node.js demo
- `demo/wasm/ruby2js-4.0.wasm` - Packed WASM (41MB)

## Phase 2: Replace Opal Demo with ruby.wasm

**Goal:** Working demo using ruby.wasm instead of Opal

**Tasks:**
1. Create build script to download pre-built Ruby WASM and pack gems
2. Update demo HTML to use the new WASM loading approach with monkey-patched require
3. Rewrite `demo/ruby2js.opal` as plain Ruby for ruby.wasm
4. Add loading indicator (WASM initialization takes ~0.4s)
5. Test all demo features work (editor, filters, options, AST display)
6. Update `docs/Rakefile` build tasks
7. Consider caching the pre-built Ruby WASM to avoid npm download on each build

**Estimated effort:** 3-5 days

## Phase 3: Cleanup

**Goal:** Remove Opal dependencies

**Tasks:**
1. Remove Opal-specific files (`demo/ruby2js.opal`, `demo/patch.opal`, `demo/filters.opal`)
2. Update `docs/Gemfile` - remove Opal dependency
3. Document new architecture and build process

**Estimated effort:** 1 day

## Total Estimated Effort: 4-6 days (reduced from 8-12)

## Technical Details

### Require Monkey-Patch

The WASI VFS in ruby.wasm has a `realpath_rec` issue that prevents normal `require` from working with packed files. The workaround:

```ruby
$PACKED_PATHS = ['/gems/ruby2js', '/gems/parser/lib', '/gems/racc/lib', '/gems/ast/lib']
$LOADED_PACKED = {}

module Kernel
  alias :original_require :require
  alias :original_require_relative :require_relative

  def require(name)
    name = name.sub(/\.rb$/, '')
    return false if $LOADED_PACKED[name]

    $PACKED_PATHS.each do |base|
      path = "#{base}/#{name}.rb"
      if File.exist?(path)
        $LOADED_PACKED[name] = true
        eval(File.read(path), TOPLEVEL_BINDING, path)
        return true
      end
    end

    original_require(name)
  end

  def require_relative(name)
    caller_path = caller_locations(1, 1).first.path
    dir = File.dirname(caller_path)
    full_path = File.join(dir, name + '.rb')

    return false if $LOADED_PACKED[full_path]

    if File.exist?(full_path)
      $LOADED_PACKED[full_path] = true
      eval(File.read(full_path), TOPLEVEL_BINDING, full_path)
      return true
    end

    original_require_relative(name)
  end
end
```

### JavaScript Loading

```javascript
import { DefaultRubyVM } from "https://cdn.jsdelivr.net/npm/@ruby/wasm-wasi@2.7.2/dist/browser/+esm";

const response = await fetch('./ruby2js-4.0.wasm');
const module = await WebAssembly.compileStreaming(response);
const { vm } = await DefaultRubyVM(module);

// Setup monkey-patch and load Ruby2JS
vm.eval(`
  $VERBOSE = nil
  def gem(*args); end
  # ... require monkey-patch ...
  ENV['RUBY2JS_PARSER'] = 'prism'
  require 'ruby2js'
`);

// Convert Ruby to JavaScript
const result = vm.eval(`Ruby2JS.convert('puts "hello"').to_s`).toString();
```

### Browser Compatibility

ruby.wasm requires:
- WebAssembly support (all modern browsers)
- WASI shim (provided by @ruby/wasm-wasi)

Minimum versions: Chrome 57+, Firefox 52+, Safari 11+, Edge 16+

## Success Criteria

- [x] Demo works with Ruby 4.0 syntax (PoC complete)
- [x] Load time < 5 seconds on broadband (0.37s achieved)
- [ ] All existing demo features work
- [ ] No Opal dependencies remain
- [ ] Documented for future maintainers

## References

- [ruby.wasm GitHub](https://github.com/ruby/ruby.wasm)
- [@ruby/wasm-wasi npm](https://www.npmjs.com/package/@ruby/wasm-wasi)
- [@ruby/head-wasm-wasi npm](https://www.npmjs.com/package/@ruby/head-wasm-wasi) (Ruby 4.0 dev)
- [Prism documentation](https://ruby.github.io/prism/)
- PoC files: `demo/wasm/poc-ruby4.html`, `demo/wasm/poc-ruby4.cjs`
