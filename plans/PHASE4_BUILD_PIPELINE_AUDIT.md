# Phase 4: Build Pipeline Audit

## Current Structure

### Build Scripts

| Script                   | Purpose                              | Output               |
| ------------------------ | ------------------------------------ | -------------------- |
| `transpile_walker.rb`    | Transpiles `prism_walker.rb`         | `dist/walker.mjs`    |
| `transpile_converter.rb` | Transpiles `converter.rb` + handlers | `dist/converter.mjs` |
| `transpile_spec.rb`      | Transpiles test specs                | `dist/*.mjs`         |

### Filter Configuration

Each script configures filters manually. Here's the comparison:

| Filter              | walker | converter | spec |
| ------------------- | ------ | --------- | ---- |
| Pragma              | ✓      | ✓         | ✓    |
| Combiner            | ✓      | ✓         | ✓    |
| Require             | ✓      | ✓         | ✗    |
| Selfhost::Core      | ✓      | ✓         | ✓    |
| Selfhost::Walker    | ✓      | ✓         | ✓    |
| Selfhost::Converter | ✗      | ✓         | ✗    |
| Selfhost::Spec      | ✗      | ✗         | ✓    |
| Polyfill            | ✓      | ✓         | ✗    |
| Functions           | ✓      | ✓         | ✓    |
| Return              | ✓      | ✓         | ✓    |
| ESM                 | ✓      | ✓         | ✓    |

### Shared Options

All scripts use:
- `eslevel: 2022`
- `comparison: :identity`
- `underscored_private: true`

Converter adds:
- `nullish_to_s: true`

### Duplication Issues

1. **Filter lists are repeated** in each script
2. **Options are repeated** in each script
3. **Post-processing logic** (export const, preamble) is inline in each script

### Runtime Files

| File                | Lines | Purpose                                              |
| ------------------- | ----- | ---------------------------------------------------- |
| `ruby2js.mjs`       | 492   | CLI tool - large due to AST inspection helpers       |
| `test_harness.mjs`  | 356   | Test framework - duplicates classes from ruby2js.mjs |
| `run_spec.mjs`      | ~20   | Runs single spec                                     |
| `run_all_specs.mjs` | 238   | Spec runner orchestration                            |

**Note**: `preamble.mjs` was found to be unused and has been deleted.

### Duplication Between ruby2js.mjs and test_harness.mjs

Both files define these classes:
- `PrismSourceBuffer` (identical)
- `PrismSourceRange` (nearly identical)
- `Namespace` (identical)
- `Hash` placeholder (identical)
- Mock globals (`RUBY_VERSION`, `RUBY2JS_PARSER`)
- Import/setup of walker and converter modules

## Recommendations

### 1. Create Shared Build Configuration

**File**: `scripts/selfhost_config.rb`

```ruby
# Shared configuration for selfhost transpilation
module SelfhostConfig
  COMMON_OPTIONS = {
    eslevel: 2022,
    comparison: :identity,
    underscored_private: true
  }

  COMMON_FILTERS = [
    Ruby2JS::Filter::Pragma,
    Ruby2JS::Filter::Combiner,
    Ruby2JS::Filter::Selfhost::Core,
    Ruby2JS::Filter::Functions,
    Ruby2JS::Filter::Return,
    Ruby2JS::Filter::ESM
  ]

  def self.walker_filters
    COMMON_FILTERS + [
      Ruby2JS::Filter::Require,
      Ruby2JS::Filter::Selfhost::Walker,
      Ruby2JS::Filter::Polyfill
    ]
  end

  def self.converter_filters
    COMMON_FILTERS + [
      Ruby2JS::Filter::Require,
      Ruby2JS::Filter::Selfhost::Walker,
      Ruby2JS::Filter::Selfhost::Converter,
      Ruby2JS::Filter::Polyfill
    ]
  end

  def self.spec_filters
    COMMON_FILTERS + [
      Ruby2JS::Filter::Selfhost::Walker,
      Ruby2JS::Filter::Selfhost::Spec
    ]
  end
end
```

**Impact**: Simplifies each transpile script to ~10 lines

### 2. Extract Shared Runtime Module

**File**: `runtime.mjs`

```javascript
// Shared runtime for selfhosted Ruby2JS
import * as Prism from '@ruby/prism';

export class PrismSourceBuffer { ... }
export class PrismSourceRange { ... }
export class Namespace { ... }
export class Hash {}

export async function initPrism() {
  return await Prism.loadPrism();
}

export function setupGlobals(prismParse) {
  globalThis.Prism = Prism;
  globalThis.PrismSourceBuffer = PrismSourceBuffer;
  globalThis.PrismSourceRange = PrismSourceRange;
  globalThis.Namespace = Namespace;
  globalThis.Hash = Hash;
  globalThis.RUBY_VERSION = "3.4.0";
  globalThis.RUBY2JS_PARSER = "prism";
  return prismParse;
}
```

**Impact**: Removes ~200 lines of duplication between files

### 3. Simplify ruby2js.mjs

The CLI file (492 lines) includes extensive AST inspection code that's only used for debugging. Consider:

1. **Keep AST inspection** - it's valuable for debugging selfhost issues
2. **Extract to separate module** - `ast_helpers.mjs` (~200 lines)

**Impact**: Makes main CLI cleaner while preserving debugging capability

### 4. Cleanup (Completed)

- ✅ **Deleted `preamble.mjs`** - confirmed unused, contained only `NotImplementedError` class that's now inlined in `transpile_converter.rb`

### Current Assessment

The build pipeline works well for its purpose. The duplication is manageable:

| Issue                     | Severity | Effort to Fix |
| ------------------------- | -------- | ------------- |
| Filter list duplication   | Low      | Low           |
| Runtime class duplication | Medium   | Medium        |
| CLI AST helpers           | Low      | Low           |

### Recommended Actions

1. ✅ **Deleted unused `preamble.mjs`**
2. **Keep current structure** - it's working and readable
3. **Document the relationship** between scripts in README
4. **Consider shared runtime** only if more CLI tools are added

### Why Not Refactor?

1. **Three scripts is manageable** - not worth abstraction overhead
2. **Filter differences are intentional** - different targets need different filters
3. **Copy-paste is acceptable** when limited to 3 files
4. **Maintenance burden is low** - these scripts rarely change

The duplication is a documentation opportunity, not a refactoring need. Each script is a clear example of how to configure selfhost transpilation for different targets.
