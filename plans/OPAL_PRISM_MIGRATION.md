# Opal Demo: Migration from whitequark Parser to Prism

## Background

The Opal demo currently uses the whitequark parser gem, which is no longer being actively maintained. Ruby's official parser going forward is Prism, which is available as a WebAssembly module (`@ruby/prism`) for browser use.

Ruby2JS already has a `PrismWalker` that converts Prism's native AST to the Parser-compatible AST format that the converter expects. This walker is used by:
- Ruby CLI (Ruby 3.3+)
- Self-hosted JS demo (transpiled to JavaScript)

This plan evaluates three options for migrating the Opal demo to use Prism.

## Options

### Option 1: Bridge JS AST to Opal

**Approach:** Use the transpiled JavaScript walker (`walker.mjs`) to produce Parser-compatible AST, then convert those JavaScript AST objects to Opal `Parser::AST::Node` instances.

```
Ruby Source (user input)
    ↓
@ruby/prism WASM (JavaScript)
    ↓
Prism AST (JavaScript objects)
    ↓
PrismWalker (JavaScript, transpiled from Ruby)
    ↓
Parser-compatible AST (JavaScript Ruby2JS.Node objects)
    ↓
Bridge: JS AST → Opal Parser::AST::Node
    ↓
Converter (Ruby, compiled by Opal)
    ↓
JavaScript Output
```

**Pros:**
- Walker already exists and is tested
- AST structure is simple and stable - easy to bridge
- Single conversion point (output AST only)
- Removes 296 lines of parser patches (`patch.opal`)

**Cons:**
- Not a "pure" Opal solution - requires Ruby2JS transpiled code
- Two different technologies in the parsing pipeline

**Effort:** ~2-3 days

| Task | Notes |
|------|-------|
| Load Prism WASM | JavaScript interop already works in Opal |
| Load walker.mjs | Standard ES module import |
| Bridge AST to Opal | Recursive conversion of ~30 node types |
| Comment handling | Use existing `associateComments` from runtime.mjs |
| Remove parser gem | Delete `patch.opal`, update requires |
| Update build process | Add walker.mjs dependency |
| Testing | Verify all filters work |

### Option 2: Opal Walker with JS Prism Bridge

**Approach:** Run the Ruby `PrismWalker` in Opal, with a proxy layer that wraps JavaScript Prism nodes to look like Ruby Prism nodes.

```
Ruby Source (user input)
    ↓
@ruby/prism WASM (JavaScript)
    ↓
Prism AST (JavaScript objects)
    ↓
Proxy Layer: JS nodes → Ruby-like interface
    ↓
PrismWalker (Ruby, compiled by Opal)
    ↓
Parser-compatible AST (Opal Parser::AST::Node)
    ↓
Converter (Ruby, compiled by Opal)
    ↓
JavaScript Output
```

**Pros:**
- Pure Opal solution - all Ruby code
- Walker changes automatically apply (no transpilation step)
- Demonstrates Opal's strength: full Ruby semantics

**Cons:**
- Proxy overhead on every node property access
- Must implement ~40 node type proxies with all their properties
- More code to write and maintain (~500+ lines)
- Proxy layer is Opal-specific code that doesn't exist elsewhere

**Effort:** ~4-6 days

| Task | Notes |
|------|-------|
| Load Prism WASM | Same as Option 1 |
| Create PrismNodeProxy base | Wrap JS node, dispatch property access |
| Implement node proxies | ~40 node types with their specific properties |
| Visitor dispatch bridge | Map JS constructor names to Ruby visit methods |
| Location proxies | Wrap location/source range objects |
| Remove parser gem | Same as Option 1 |
| Testing | More extensive - new proxy code |

## Recommendation: Option 1

**We recommend Option 1** for the following reasons:

### 1. Leverages Existing Work

The JavaScript walker already exists, is thoroughly tested (full transliteration suite passes), and is maintained via transpilation from the same Ruby source. There's no need to recreate this functionality in a proxy layer.

### 2. Simpler Bridge

Option 1 bridges at the AST output level - a simple, stable data structure with ~30 node types. Option 2 bridges at the Prism node level, requiring proxies for ~40 node types with all their properties, plus location objects, plus visitor dispatch.

### 3. Better Performance

Option 2 incurs proxy overhead on every property access during tree walking. The walker makes hundreds of property accesses per parse. Option 1 does a single conversion pass over the output AST.

### 4. Illustrates Tool Strengths

The hybrid approach showcases when to use each tool:

| Tool | Strength | Used For |
|------|----------|----------|
| **Ruby2JS** | Direct JS interop, static conversion | Walker (interfaces with JS Prism API) |
| **Opal** | Full Ruby semantics, no pragmas needed | Converter + Filters (complex Ruby code) |

Ruby2JS excels at code that needs to interface directly with JavaScript APIs - the walker calls Prism WASM methods, accesses JS object properties, and produces JS-compatible output. This is exactly what Ruby2JS is designed for.

Opal excels at running complex Ruby code that uses dynamic features, metaprogramming, or Ruby semantics that don't map cleanly to JavaScript. The converter with its 60+ handlers and 23 filters is a better fit for Opal.

### 5. Maintenance

With Option 1, walker updates flow automatically via transpilation. With Option 2, any new Prism node types or property changes require updating the proxy layer.

## Implementation Plan (Option 1)

### Phase 1: Infrastructure

1. **Update `demo/ruby2js.opal`** to load Prism WASM and walker.mjs
2. **Create AST bridge** (`demo/ast_bridge.opal`) - convert JS AST to Opal nodes
3. **Update build process** to include walker.mjs in dependencies

### Phase 2: Integration

4. **Replace parser call** - use Prism + walker instead of `Parser::CurrentRuby`
5. **Bridge comments** - convert JS comment associations to Opal format
6. **Remove `patch.opal`** - no longer needed without parser gem

### Phase 3: Cleanup & Testing

7. **Test all filters** - ensure no regressions
8. **Update documentation** - note Prism requirement
9. **Benchmark** - compare bundle size and performance

## AST Bridge Sketch

```ruby
# demo/ast_bridge.opal
module Ruby2JS
  module ASTBridge
    def self.convert(js_node)
      return nil if `js_node == null`

      type = `js_node.type`.to_sym
      children = `js_node.children`.map { |child| convert_child(child) }
      location = convert_location(`js_node.loc`)

      Parser::AST::Node.new(type, children, location: location)
    end

    def self.convert_child(child)
      if `child == null`
        nil
      elsif `typeof child === 'string'`
        child
      elsif `typeof child === 'number'`
        child
      elsif `child.type !== undefined`
        convert(child)
      elsif `Array.isArray(child)`
        child.map { |c| convert_child(c) }
      else
        child
      end
    end

    def self.convert_location(js_loc)
      return nil if `js_loc == null`
      # Create Parser::Source::Map compatible object
      # ... implementation details
    end
  end
end
```

## Future Considerations

- **Full self-hosting**: Eventually the entire demo could use the self-hosted approach (no Opal), but filters need to be transpiled first
- **Shared runtime**: The `runtime.mjs` comment handling could be shared between Opal and self-hosted demos
- **Bundle size**: Removing the parser gem should reduce bundle size; measure actual impact

## References

- [plans/SELF_HOSTING.md](./SELF_HOSTING.md) - Self-hosted demo architecture
- [demo/selfhost/](../demo/selfhost/) - Transpiled walker and converter
- [lib/ruby2js/prism_walker.rb](../lib/ruby2js/prism_walker.rb) - Ruby walker source
- [@ruby/prism npm package](https://www.npmjs.com/package/@ruby/prism)
