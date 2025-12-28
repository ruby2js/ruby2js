# Ruby in JavaScript: Comparing Approaches

Three technologies enable running Ruby code in JavaScript environments: Opal, Ruby WASM, and Ruby2JS. Each has distinct strengths and trade-offs.

## Technology Overview

### Opal (Ruby → JavaScript Compilation)

Opal compiles Ruby source code to JavaScript, emulating Ruby's object model and semantics at runtime.

**Advantages:**
- **Full Ruby semantics** - Runs actual Ruby code with complete language support (blocks, procs, metaprogramming, `method_missing`, etc.)
- **Existing ecosystem** - Mature project with Rails integration (opal-rails), many gems already ported
- **Runtime flexibility** - Can `eval` Ruby code at runtime
- **Familiar debugging** - Errors reference Ruby code and line numbers
- **Proven approach** - Used in production (Volt framework, etc.)

**Disadvantages:**
- **Large bundle size** - ~5MB for full runtime
- **Performance overhead** - Ruby object model emulated in JS, method dispatch is slower
- **Not native JS** - Generated code doesn't interop naturally with JS libraries
- **Startup latency** - Loading and initializing the Ruby runtime takes time
- **Memory usage** - Ruby object model requires more memory than native JS

### Ruby WASM (WebAssembly)

Ruby WASM runs the actual CRuby VM compiled to WebAssembly.

**Advantages:**
- **True Ruby VM** - CRuby itself running in browser via WASM
- **Complete compatibility** - Can run any Ruby code, including C extensions compiled to WASM
- **Native gems** - Potential to run real gems (nokogiri, etc.) via WASM compilation
- **Consistent behavior** - Exact same semantics as server-side Ruby
- **Official support** - Backed by Ruby core team

**Disadvantages:**
- **Very large bundle** - Full Ruby VM is several MB (larger than Opal)
- **Cold start** - WASM instantiation and Ruby boot time is significant
- **Memory intensive** - Full VM in memory, not optimized for browser constraints
- **JS interop friction** - Crossing WASM boundary has overhead and complexity
- **Still maturing** - ruby.wasm is relatively new, tooling is evolving
- **Threading limitations** - Ruby threading doesn't map cleanly to browser/WASM model

### Ruby2JS (Transpilation)

Ruby2JS transpiles Ruby source to idiomatic JavaScript, with optional filters for framework-specific patterns.

**Advantages:**
- **Small bundle** - ~200KB + Prism WASM for self-hosted transpilation
- **Native JS output** - Generated code is idiomatic JavaScript, works naturally with JS ecosystem
- **No runtime overhead** - Runs at native JS speed, no interpretation layer
- **Better debugging** - Sourcemaps allow debugging Ruby in browser DevTools
- **Tree-shakeable** - Only includes code actually used
- **Fast startup** - No VM to boot, just regular JS execution
- **Dual-target development** - Same Ruby code can run server-side (real Ruby) and client-side (transpiled)

**Disadvantages:**
- **Limited Ruby support** - Not all Ruby features can be transpiled (no `eval`, limited metaprogramming)
- **Semantic differences** - Some Ruby behaviors don't map 1:1 to JavaScript
- **Filter complexity** - Framework patterns (e.g., Rails) require specialized filters
- **No runtime Ruby** - Can't dynamically execute Ruby code in browser
- **Ongoing maintenance** - Need to update filters as Ruby evolves
- **Learning curve** - Developers must understand what transpiles and what doesn't

## Comparison Matrix

| Aspect             | Opal   | Ruby WASM  | Ruby2JS                              |
| ------------------ | ------ | ---------- | ------------------------------------ |
| Bundle size        | ~5MB   | ~10MB+     | ~200KB                               |
| Ruby compatibility | ~95%   | ~100%      | ~70%                                 |
| JS interop         | Poor   | Complex    | Native                               |
| Performance        | Slow   | Medium     | Fast                                 |
| Startup time       | Slow   | Very slow  | Fast                                 |
| Metaprogramming    | Yes    | Yes        | Limited                              |
| Debugging          | Good   | Improving  | Excellent (sourcemaps)               |
| Maturity           | Mature | Developing | Mature (core), Early (Rails filters) |

## End-User Use Cases

### Opal

**Internal/Enterprise Tools**
- Admin dashboards where bundle size is irrelevant (employees have fast connections)
- Tools built by Ruby teams who want to share code between server and client
- Complex business logic that benefits from Ruby's expressiveness

**Interactive Documentation**
- Ruby API docs with live "try it" code editors
- Educational platforms teaching Ruby (run student code in browser)

**Electron/Desktop Apps**
- Bundle size matters less when installed locally
- Full Ruby semantics available for complex desktop applications
- Teams already invested in Ruby wanting to build cross-platform apps

**Legacy Migration**
- Gradual migration of server-rendered Rails apps to SPA
- Reuse existing Ruby business logic without rewriting in JavaScript

### Ruby WASM

**Server-Side JavaScript Environments**
- Running Ruby gems in Node.js/Deno/Bun workers
- Serverless functions that need specific Ruby gems (especially those with C extensions)
- Microservices that must run Ruby code in a JS-based infrastructure

**Offline-First Applications**
- PWAs where initial download is acceptable if app works offline indefinitely
- Field data collection apps (download once, use in remote areas)
- Kiosk/embedded applications with persistent local storage

**Gem Compatibility Requirements**
- Applications that absolutely need specific gems (nokogiri, etc.)
- Data processing pipelines that rely on Ruby libraries
- Scientific/analytical tools using Ruby's numeric libraries

**Sandboxed Ruby Execution**
- Online Ruby REPLs and coding playgrounds
- Code assessment platforms (run untrusted Ruby safely in browser)
- CI/CD previews of Ruby applications

### Ruby2JS

**Offline-Capable Rails Apps (ERB Filter)**

Rails applications needing offline capability for specific workflows benefit from Ruby2JS's ERB filter. Instead of running Rails in the browser, convert templates at build time:

```
Build/Deploy Time                    Runtime (Browser)
─────────────────                    ─────────────────
ERB templates                        Native JS functions
      ↓                                    ↓
Ruby2JS + ERB filter        →        function heat(data) {
      ↓                                return `<div>...</div>`;
JavaScript functions                 }
```

- Templates convert once at build/deploy, not in browser
- Zero Ruby overhead at runtime - just native JS functions
- Rails remains server and source of truth
- Client fetches data, hydrates, renders with converted templates
- IndexedDB queues changes for sync when back online

Example: A scoring application for live events where judges need to work during WiFi outages. Server computes and normalizes data, client renders using converted ERB templates, scores queue locally until connectivity returns.

**Why Ruby2JS over Opal/WASM for this use case:**
- Templates are known at build time (no runtime transpilation needed)
- Converted templates are ~0KB overhead (just JS functions)
- Native JS output means seamless access to browser APIs (IndexedDB, Service Workers, Fetch, etc.)
- Direct access to the npm ecosystem (Hotwire, Trix, sql.js, etc.) via standard `import`
- Opal and Ruby WASM require crossing a bridge to use browser APIs and npm packages
- Opal (~5MB) and Ruby WASM (~41MB) solve a different problem: running Ruby you don't know until runtime

**Ecosystem tradeoffs:**
- Ruby WASM: Full gem ecosystem including C extensions
- Opal: Gems without C extensions (substantial but limited)
- Ruby2JS: npm ecosystem (vast, browser-optimized)

For server-side processing, gem access may be preferable. For browser applications, npm ecosystem access is a significant advantage—libraries like `@hotwired/turbo`, `@hotwired/stimulus`, `trix`, and `sql.js` are npm packages designed for the browser.

**Performance-Critical Browser Apps**
- Real-time collaborative tools where latency matters
- Data visualization dashboards with frequent updates
- Mobile web apps where every KB and millisecond counts

**Hybrid Ruby/JS Codebases**
- Stimulus controllers written in Ruby syntax
- View components shared between Rails server and JS frontend
- API clients with shared validation logic

**Static Site Enhancement**
- Jekyll/Bridgetown sites with interactive Ruby-syntax components
- Documentation sites with live examples (small overhead)
- Marketing sites where Core Web Vitals matter

**Edge/CDN Deployment**
- Cloudflare Workers, Deno Deploy, Vercel Edge
- Tight size limits make transpilation the only viable option
- Low-latency requirements preclude VM startup

**Embedded Widgets**
- Third-party widgets embedded in customer sites (bundle size critical)
- Chat widgets, forms, or tools distributed as `<script>` tags
- Browser extensions where footprint must be minimal

## Decision Framework

| If you need...                                           | Choose               |
| -------------------------------------------------------- | -------------------- |
| Run existing Ruby code unchanged                         | Ruby WASM            |
| Smallest possible bundle                                 | Ruby2JS              |
| Full metaprogramming (`method_missing`, `define_method`) | Opal or Ruby WASM    |
| Native JS library interop                                | Ruby2JS              |
| Run Ruby gems with C extensions                          | Ruby WASM            |
| Fast cold start                                          | Ruby2JS              |
| `eval` or runtime code generation                        | Opal or Ruby WASM    |
| Deploy to edge/serverless with size limits               | Ruby2JS              |
| Team knows Ruby, not JS                                  | Opal                 |
| Gradual adoption in existing JS app                      | Ruby2JS              |
| Offline templates for Rails app                          | Ruby2JS (ERB filter) |

## Context: Ruby2JS-on-Rails Demo

For the [Ruby2JS-on-Rails demo](./RUBY2JS_ON_RAILS.md) goal (blog tutorial in browser), Ruby2JS is the appropriate choice because:

1. The priority is **showcasing Ruby2JS capabilities**, not running arbitrary Ruby
2. Bundle size matters for browser demos
3. Native JS output means the generated code is inspectable and debuggable
4. The Rails filters being developed (model, controller, routes, etc.) provide the DSL support needed

For **running a full Rails app unchanged**, Ruby WASM would be better (accepting the size/performance tradeoffs), since it can run the actual Rails framework code.

## References

- [Opal](https://opalrb.com/) - Ruby to JavaScript compiler
- [ruby.wasm](https://github.com/ruby/ruby.wasm) - Ruby in WebAssembly
- [Ruby2JS](https://www.ruby2js.com/) - Ruby to JavaScript transpiler
