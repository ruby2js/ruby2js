# Combo Box Migration: Opal to Selfhost

## Status: Planning

This plan outlines migrating the interactive combo boxes in the documentation site from the Opal-based Ruby2JS (~5MB) to the selfhost version (~500KB).

## Current Architecture

### Opal Demo (Current)
```
docs/src/demo/ruby2js.js    (~5MB, Opal-compiled)
    ↓
Ruby2JS.convert(ruby, options)
    ↓
options.filters = ["functions", "esm"]  (string names)
    ↓
Looks up in Ruby2JS::Filter.registered_filters
```

### Selfhost Demo (Target)
```
demo/selfhost/ruby2js.js    (~500KB, transpiled)
    ↓
convert(source, options)
    ↓
options.filters = [functionsFilter, esmFilter]  (module references)
    ↓
Filters loaded via dynamic import()
```

## Filter Availability

### Available in Selfhost
| Filter | Combo Box Usage | Status |
|--------|-----------------|--------|
| functions | 73 uses | Ready |
| esm | 25 uses | Ready |
| pragma | 19 uses | Ready |
| model | 2 uses | Ready |
| controller | 1 use | Ready |
| routes | 1 use | Ready |
| camelCase | 1 use | Ready |
| active_support | - | Ready |
| cjs | - | Ready |
| erb | - | Ready |
| phlex | - | Ready |
| polyfill | - | Ready |
| return | - | Ready |
| tagged_templates | - | Ready |

### Missing from Selfhost
| Filter | Combo Box Usage | Blocker |
|--------|-----------------|---------|
| react | 9 uses | Not transpiled |
| stimulus | 7 uses | Not transpiled |
| lit | 2 uses | Not transpiled |
| jest | 2 uses | Not transpiled |

## Pages by Filter Requirements

### Ready for Selfhost (All filters available)
- `users-guide/introduction.md` - functions only
- `users-guide/patterns.md` - functions, pragma
- `users-guide/pragmas.md` - pragma, functions
- `users-guide/javascript-only.md` - functions, esm, pragma
- `users-guide/ruby2js-on-rails.md` - model, controller, routes, esm, functions

### Blocked (Missing filters)
- `filters/react.md` - needs react filter
- `filters/lit.md` - needs lit filter
- `filters/jest.md` - needs jest filter
- `_examples/react/*` - needs react filter
- `_examples/stimulus/*` - needs stimulus filter
- `_examples/rails/*` - needs react/preact/lit filters

## Migration Approaches

### Option A: Incremental Migration

Migrate pages one at a time based on filter availability.

**Pros:**
- Lower risk, can test each page individually
- Users see improvements immediately
- Can pause migration if issues arise

**Cons:**
- Need to maintain both Opal and selfhost bundles
- More complex logic to choose which converter to use
- Longer overall timeline

**Implementation:**
1. Add selfhost bundle to docs site alongside Opal
2. Add `data-converter="selfhost"` attribute to combo boxes
3. Modify demo controller to check attribute and use appropriate converter
4. Migrate pages one by one, testing each
5. Remove Opal bundle when all pages migrated

### Option B: All-at-Once Migration

Transpile missing filters first, then switch everything at once.

**Pros:**
- Simpler architecture (one converter)
- Clean cutover
- No hybrid complexity

**Cons:**
- Blocked until all 4 filters transpiled
- Higher risk at switchover
- Delays any benefits until complete

**Implementation:**
1. Transpile react, stimulus, lit, jest filters
2. Add filter specs to selfhost test suite
3. Build comprehensive filter loader for browser
4. Update demo controller to use selfhost
5. Remove Opal bundle

### Option C: Hybrid with Fallback

Use selfhost by default, fall back to Opal for missing filters.

**Pros:**
- Most pages get smaller bundle immediately
- Graceful handling of missing filters
- Progressive improvement

**Cons:**
- Two bundles loaded on some pages
- Complex loading logic
- May confuse users if behavior differs

## Recommended Approach: Option A (Incremental)

The incremental approach is recommended because:
1. Most combo boxes (117 of 137) only need available filters
2. The 4 missing filters are already on the roadmap for selfhost specs
3. Users get the ~90% size reduction immediately for most pages
4. Lower risk allows faster initial deployment

## Implementation Plan

### Phase 1: Infrastructure (1-2 days)

**1.1 Create Browser Filter Loader**

Create `docs/src/demo/selfhost/filter-loader.js`:
```javascript
const filterCache = new Map();

export async function loadFilter(name) {
  if (filterCache.has(name)) {
    return filterCache.get(name);
  }

  // Normalize name (model -> rails/model for Rails filters)
  const path = normalizeFilterPath(name);

  try {
    await import(`./filters/${path}.js`);

    // Find in Ruby2JS.Filter by normalized name
    const normalize = s => s.toLowerCase().replace(/[_/]/g, '');
    const available = Object.keys(Ruby2JS.Filter || {});
    const actualName = available.find(n => normalize(n) === normalize(name));

    if (actualName) {
      filterCache.set(name, Ruby2JS.Filter[actualName]);
      return Ruby2JS.Filter[actualName];
    }
  } catch (e) {
    console.warn(`Filter ${name} not available in selfhost`);
    return null;
  }
}

export async function loadFilters(names) {
  const filters = await Promise.all(names.map(loadFilter));
  return filters.filter(f => f !== null);
}
```

**1.2 Update Demo Controller**

Modify `demo/controllers/ruby_controller.js.rb` to support both converters:
```ruby
async def convert()
  return unless targets.size > 0 and @rubyEditor

  ruby = @rubyEditor.state.doc.to_s

  begin
    if use_selfhost?
      js = await selfhost_convert(ruby, @options)
    else
      js = Ruby2JS.convert(ruby, @options)
    end
    targets.each {|target| target.contents = js.to_s}
  rescue => e
    targets.each {|target| target.exception = e.to_s}
  end
end

def use_selfhost?
  # Check if selfhost is available and all required filters are supported
  return false unless defined?(SelfhostRuby2JS)

  filter_names = @options[:filters] || []
  filter_names.all? { |name| SELFHOST_FILTERS.include?(name) }
end
```

**1.3 Copy Selfhost Bundle to Docs**

Update `docs/Rakefile` to copy selfhost files:
```ruby
task :selfhost_for_demo do
  # Copy main bundle
  cp "#{root}/demo/selfhost/ruby2js.js", "#{dest}/selfhost/ruby2js.js"

  # Copy filters
  mkdir_p "#{dest}/selfhost/filters"
  SELFHOST_FILTERS.each do |name|
    path = name.include?('/') ? name : name
    cp "#{root}/demo/selfhost/filters/#{path}.js", "#{dest}/selfhost/filters/#{path}.js"
  end
end
```

### Phase 2: Migrate User's Guide Pages (1 day)

These pages only use functions, esm, pragma filters.

1. `users-guide/introduction.md`
2. `users-guide/patterns.md`
3. `users-guide/pragmas.md`
4. `users-guide/javascript-only.md`
5. `users-guide/ruby2js-on-rails.md`

**Testing:**
- Verify each combo box converts correctly
- Compare output with Opal version
- Check no console errors

### Phase 3: Migrate Filter Documentation Pages (1 day)

Pages that only need available filters:

1. `filters/pragma.md`
2. `filters/active_support.md`
3. `filters/erb.md`
4. `filters/phlex.md`

**Hold for Phase 5:**
- `filters/react.md` - needs react
- `filters/lit.md` - needs lit
- `filters/jest.md` - needs jest

### Phase 4: Transpile Missing Filters (2-3 days)

Transpile the 4 remaining filters needed by combo boxes:

**4.1 React Filter**
```bash
bundle exec ruby scripts/transpile_filter.rb \
  ../../lib/ruby2js/filter/react.rb > filters/react.js
```

Add to spec manifest, fix transpilation issues.

**4.2 Stimulus Filter**
```bash
bundle exec ruby scripts/transpile_filter.rb \
  ../../lib/ruby2js/filter/stimulus.rb > filters/stimulus.js
```

**4.3 Lit Filter**
```bash
bundle exec ruby scripts/transpile_filter.rb \
  ../../lib/ruby2js/filter/lit.rb > filters/lit.js
```

**4.4 Jest Filter**
```bash
bundle exec ruby scripts/transpile_filter.rb \
  ../../lib/ruby2js/filter/jest.rb > filters/jest.js
```

### Phase 5: Complete Migration (1 day)

1. Migrate remaining filter doc pages
2. Migrate example pages
3. Remove Opal bundle from docs
4. Update documentation about demo

### Phase 6: Cleanup (1 day)

1. Remove hybrid converter logic
2. Simplify demo controller
3. Update SELF_HOSTING.md plan
4. Announce in changelog

## Size Comparison

| Component | Opal | Selfhost | Savings |
|-----------|------|----------|---------|
| Core bundle | 5MB | 500KB | 90% |
| functions filter | included | 75KB | - |
| esm filter | included | 23KB | - |
| Rails filters | included | 100KB | - |
| **Total (typical page)** | **5MB** | **~700KB** | **86%** |

## Risks and Mitigations

### Risk: Conversion output differs between Opal and selfhost
**Mitigation:** Run comparison tests on all combo box examples before migration

### Risk: Missing edge cases in selfhost filters
**Mitigation:** Ensure filter specs pass for all "ready" specs before migration

### Risk: Browser compatibility issues with selfhost
**Mitigation:** Test on major browsers (Chrome, Firefox, Safari, Edge)

### Risk: Performance regression
**Mitigation:** Measure and compare conversion time; selfhost should be faster

## Success Criteria

1. All combo boxes produce identical output to Opal version
2. Page load time reduced by 50%+ (smaller bundle)
3. No console errors on any documentation page
4. All selfhost filter specs passing
5. Documentation updated to reflect new architecture

## Timeline Estimate

| Phase | Duration | Dependencies |
|-------|----------|--------------|
| Phase 1: Infrastructure | 1-2 days | None |
| Phase 2: User's Guide | 1 day | Phase 1 |
| Phase 3: Filter Docs (partial) | 1 day | Phase 1 |
| Phase 4: Transpile Filters | 2-3 days | None (parallel) |
| Phase 5: Complete Migration | 1 day | Phase 4 |
| Phase 6: Cleanup | 1 day | Phase 5 |

**Total: 7-9 days** (can be reduced by parallelizing Phase 4)

## References

- [SELF_HOSTING.md](./SELF_HOSTING.md) - Selfhost architecture
- [demo/selfhost/ruby2js-cli.js](../demo/selfhost/ruby2js-cli.js) - CLI filter loading example
- [spec_manifest.json](../demo/selfhost/spec_manifest.json) - Filter test status
