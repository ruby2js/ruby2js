# Runtime Targets and Configuration Plan

Follow-on to [MULTI_TARGET_ARCHITECTURE.md](./MULTI_TARGET_ARCHITECTURE.md). Adds centralized YAML configuration and support for Bun/Deno as server-side runtime targets.

## Part 1: Configuration File (config/ruby2js.yml)

### Motivation

The current build process hardcodes transpilation options in `scripts/build.rb`:

```ruby
OPTIONS = {
  eslevel: 2022,
  include: [:class, :call],
  autoexports: true,
  filters: [...]
}.freeze
```

A YAML configuration file provides:
- Centralized, declarative configuration
- Easy switching between option sets
- Consistency with `config/database.yml` pattern
- Format compatible with JavaScript builds (unlike `config/ruby2js.rb`)

### File Location

```
config/ruby2js.yml
```

### Configuration Options

Based on [options.md](/docs/src/_docs/options.md), the following options are supported in YAML configuration:

| Option                  | Type           | Status | Description                                                                                         |
| ----------------------- | -------------- | ------ | --------------------------------------------------------------------------------------------------- |
| `preset`                | boolean        | ✅     | Enable preset configuration (functions, esm, pragma, return filters + ES2022 + identity comparison) |
| `eslevel`               | integer        | ✅     | ECMAScript target level (2020-2025)                                                                 |
| `filters`               | array          | ✅     | Additional filters to apply (selfhost-ready filters only)                                           |
| `disable_filters`       | array          | ✅     | Filters to remove (when using preset)                                                               |
| `autoexports`           | boolean/string | ✅     | Auto-export top-level declarations (true, false, or "default")                                      |
| `autoimports`           | hash           | ✅     | Map constants to import sources                                                                     |
| `comparison`            | string         | ✅     | "equality" or "identity"                                                                            |
| `include`               | array          | ✅     | Methods to opt-in for conversion                                                                    |
| `exclude`               | array          | ✅     | Methods to exclude from conversion                                                                  |
| `include_all`           | boolean        | ✅     | Opt-in to all available conversions                                                                 |
| `include_only`          | array          | ✅     | Only convert these methods                                                                          |
| `module`                | string         | ✅     | "esm" or "cjs"                                                                                      |
| `nullish_to_s`          | boolean        | ✅     | Wrap to_s/interpolation for nil safety                                                              |
| `or`                    | string         | ✅     | "auto", "nullish", or "logical"                                                                     |
| `truthy`                | string         | ✅     | "ruby" or "js"                                                                                      |
| `strict`                | boolean        | ✅     | Add "use strict" directive                                                                          |
| `underscored_private`   | boolean        | ✅     | Use `_x` instead of `#x` for private fields                                                         |
| `width`                 | integer        | ✅     | Target output width                                                                                 |
| `template_literal_tags` | array          | ✅     | Methods to convert to tagged templates                                                              |

### Available Filters in FILTER_MAP

Filters available for use in `filters:` configuration (selfhost-ready):

| Filter             | Module                           |
| ------------------ | -------------------------------- |
| `functions`        | Ruby2JS::Filter::Functions       |
| `esm`              | Ruby2JS::Filter::ESM             |
| `cjs`              | Ruby2JS::Filter::CJS             |
| `return`           | Ruby2JS::Filter::Return          |
| `erb`              | Ruby2JS::Filter::Erb             |
| `pragma`           | Ruby2JS::Filter::Pragma          |
| `camelCase`        | Ruby2JS::Filter::CamelCase       |
| `tagged_templates` | Ruby2JS::Filter::TaggedTemplates |
| `phlex`            | Ruby2JS::Filter::Phlex           |
| `stimulus`         | Ruby2JS::Filter::Stimulus        |
| `active_support`   | Ruby2JS::Filter::ActiveSupport   |
| `securerandom`     | Ruby2JS::Filter::SecureRandom    |
| `nokogiri`         | Ruby2JS::Filter::Nokogiri        |
| `haml`             | Ruby2JS::Filter::Haml            |
| `jest`             | Ruby2JS::Filter::Jest            |
| `rails/model`      | Ruby2JS::Filter::Rails::Model    |
| `rails/controller` | Ruby2JS::Filter::Rails::Controller |
| `rails/routes`     | Ruby2JS::Filter::Rails::Routes   |
| `rails/seeds`      | Ruby2JS::Filter::Rails::Seeds    |
| `rails/helpers`    | Ruby2JS::Filter::Rails::Helpers  |
| `rails/migration`  | Ruby2JS::Filter::Rails::Migration |

**Pending selfhost readiness:** react, node, jsx, lit, alpine, turbo, action_cable

### Example Configuration

```yaml
# config/ruby2js.yml

# Use preset as base (recommended)
preset: true

# ECMAScript target
eslevel: 2022

# Additional filters beyond preset
filters:
  - camelCase
  - active_functions

# Disable specific preset filters
disable_filters:
  - return

# Export behavior
autoexports: default

# Auto-import mappings
autoimports:
  "[LitElement, css, html]": "lit"
  "[ref, reactive]": "vue"

# Method conversion options
include:
  - class
  - call
exclude:
  - each

# Comparison and operators
comparison: identity
or: auto
truthy: js

# Module format
module: esm

# Private field style (for inheritance compatibility)
underscored_private: true

# Nil-safe string operations
nullish_to_s: true

# Output formatting
width: 80
strict: true
```

### Environment-Specific Configuration

Support environment sections (like database.yml):

```yaml
# config/ruby2js.yml

default: &default
  preset: true
  eslevel: 2022
  autoexports: true
  comparison: identity

development:
  <<: *default
  strict: false

production:
  <<: *default
  strict: true
  width: 120

test:
  <<: *default
```

### Build Integration

The build script loads and merges configuration:

```ruby
def load_ruby2js_config
  env = ENV['RAILS_ENV'] || ENV['NODE_ENV'] || 'development'
  config_path = File.join(DEMO_ROOT, 'config/ruby2js.yml')

  return {} unless File.exist?(config_path)

  config = YAML.load_file(config_path)

  # Support environment-specific or flat config
  if config.key?(env)
    config[env]
  elsif config.key?('default')
    config['default']
  else
    config
  end
end

def build_options
  base = load_ruby2js_config

  # Convert string keys to symbols
  options = base.transform_keys(&:to_sym)

  # Handle filter names -> filter modules
  if options[:filters]
    options[:filters] = options[:filters].map do |name|
      Ruby2JS::Filter.const_get(name.to_s.split('_').map(&:capitalize).join)
    end
  end

  options
end
```

---

## Part 2: Runtime Targets (Bun/Deno)

### Current State

The multi-target architecture derives target from database adapter:

| Database Adapter           | Target  |
| -------------------------- | ------- |
| dexie, sqljs               | browser |
| pg, mysql2, better_sqlite3 | node    |

### Proposed Extension

Add `runtime` option for non-browser targets:

| Database Adapter | Runtime        | Result  |
| ---------------- | -------------- | ------- |
| dexie, sqljs     | (ignored)      | browser |
| pg, mysql2, etc. | node (default) | node    |
| pg, mysql2, etc. | bun            | bun     |
| pg, mysql2, etc. | deno           | deno    |

### Configuration

#### Option 1: In ruby2js.yml

```yaml
# config/ruby2js.yml

# Runtime target for server-side code
# Only applies when database is not browser-based (dexie/sqljs)
# Options: node (default), bun, deno
runtime: node
```

#### Option 2: In database.yml

```yaml
# config/database.yml

production:
  adapter: pg
  runtime: bun  # Use Bun instead of Node.js
  host: localhost
  database: my_app
```

#### Option 3: Environment Variable

```bash
RUNTIME=deno npm run build
```

**Recommendation:** Support all three with priority: `RUNTIME` env > `database.yml` > `ruby2js.yml` > default (node)

### Implementation Changes

#### 1. Node Filter: Use `node:` Prefix

Update `lib/ruby2js/filter/node.rb` to use `node:` prefixed imports (required for Deno, compatible with Node 16+ and Bun):

```ruby
def import_fs
  @import_fs ||= s(:import, ['node:fs'], s(:attr, nil, :fs))
end

def import_fs_promises
  @import_fs_promises ||= s(:import, ['node:fs/promises'], s(:attr, nil, :fs))
end

def import_path
  @import_path ||= s(:import, ['node:path'], s(:attr, nil, :path))
end

def import_os
  @import_os ||= s(:import, ['node:os'], s(:attr, nil, :os))
end

def import_child_process
  @import_child_process ||= s(:import, ['node:child_process'],
      s(:attr, nil, :child_process))
end
```

This single change makes the Node filter compatible with all three runtimes.

#### 2. Runtime-Specific Targets Directory

Extend the targets structure for runtime-specific code:

```
lib/targets/
├── browser/
│   └── rails.js
└── server/
    ├── common/
    │   └── rails.js      # Shared server code
    ├── node/
    │   └── server.js     # Node-specific (http.createServer)
    ├── bun/
    │   └── server.js     # Bun-specific (Bun.serve)
    └── deno/
        └── server.js     # Deno-specific (Deno.serve)
```

#### 3. Server Entry Points

**Node (lib/targets/server/node/server.js):**
```javascript
import http from 'node:http';
import { router } from '../config/routes.js';

const server = http.createServer(async (req, res) => {
  await router.dispatch(req, res);
});

server.listen(process.env.PORT || 3000);
```

**Bun (lib/targets/server/bun/server.js):**
```javascript
import { router } from '../config/routes.js';

Bun.serve({
  port: process.env.PORT || 3000,
  async fetch(req) {
    return await router.dispatch(req);
  }
});
```

**Deno (lib/targets/server/deno/server.js):**
```javascript
import { router } from '../config/routes.js';

Deno.serve({ port: Number(Deno.env.get("PORT")) || 3000 }, async (req) => {
  return await router.dispatch(req);
});
```

#### 4. Build Script Updates

```ruby
class SelfhostBuilder
  # Runtime options for server-side targets
  SERVER_RUNTIMES = ['node', 'bun', 'deno'].freeze

  def load_runtime_config
    # Priority: RUNTIME env > database.yml > ruby2js.yml > default
    return ENV['RUNTIME'].downcase if ENV['RUNTIME']

    db_config = load_database_config
    return db_config['runtime'] if db_config['runtime']

    r2js_config = load_ruby2js_config
    return r2js_config['runtime'] if r2js_config['runtime']

    'node'  # Default
  end

  def build
    # ... existing code ...

    @database = db_config['adapter'] || 'sqljs'
    @target = BROWSER_DATABASES.include?(@database) ? 'browser' : 'server'
    @runtime = @target == 'server' ? load_runtime_config : nil

    # Validate runtime
    if @runtime && !SERVER_RUNTIMES.include?(@runtime)
      raise "Unknown runtime: #{@runtime}. Valid options: #{SERVER_RUNTIMES.join(', ')}"
    end

    # ... rest of build ...
  end

  def copy_lib_files
    if @target == 'browser'
      # Copy browser target files
      copy_from('lib/targets/browser')
    else
      # Copy common server files
      copy_from('lib/targets/server/common')
      # Copy runtime-specific files
      copy_from("lib/targets/server/#{@runtime}")
    end
  end
end
```

### Documentation Updates

Update `docs/src/_docs/filters/node.md`:

```markdown
## Runtime Compatibility

The Node filter generates code compatible with:

| Runtime | Version | Notes                                |
| ------- | ------- | ------------------------------------ |
| Node.js | 16+     | Full support                         |
| Bun     | 1.0+    | Full support                         |
| Deno    | 1.36+   | Full support (2.4.0+ for `Dir.glob`) |

All imports use the `node:` prefix (e.g., `node:fs`) which is supported
by all three runtimes.

### Dir.glob / fs.globSync

Requires newer runtime versions:
- Node.js 22+
- Bun 1.2.2+
- Deno 2.4.0+
```

---

## Implementation Phases

### Phase 1: YAML Configuration ✅ COMPLETE

1. ✅ Created `config/ruby2js.yml` with environment-specific configuration
2. ✅ Updated `build.rb` to load and merge YAML config via `load_ruby2js_config()`
3. ✅ Added `build_options()` method to merge YAML with hardcoded OPTIONS
4. ✅ Implemented `preset: true` option for standard configuration (functions, esm, pragma, return + ES2022 + identity)
5. ✅ Implemented `disable_filters` option to remove filters from preset/base
6. ✅ Expanded `FILTER_MAP` with selfhost-ready filters (cjs, active_support, securerandom, jest, tagged_templates, nokogiri, haml)
7. ⏸️ Formal tests for configuration loading (deferred - verified via smoke tests)
8. ⏸️ Additional filters (react, node, jsx, lit, alpine, turbo, action_cable) blocked pending selfhost readiness

### Phase 2: Node Filter Updates ✅ COMPLETE

1. ✅ Changed all bare imports to `node:` prefix in `lib/ruby2js/filter/node.rb`
2. ✅ Updated `spec/node_spec.rb` tests to expect `node:` prefixed imports
3. ⏸️ Update node.md documentation (deferred - minor doc update)

### Phase 3: Runtime Targets ✅ COMPLETE

1. ✅ Created runtime-specific targets in `lib/targets/{node,bun,deno}/rails.js`
2. ✅ Bun target uses `Bun.serve` with Fetch API
3. ✅ Deno target uses `Deno.serve` with Fetch API
4. ✅ Updated build script with `load_runtime_config()` and `SERVER_RUNTIMES`
5. ✅ Build copies appropriate runtime target based on RUNTIME env/config

### Phase 4: Documentation & Polish ✅ COMPLETE

1. ✅ This plan updated with completion status
2. ⏸️ Add runtime examples to User's Guide (deferred - low priority)
3. ✅ Tested all combinations (browser + 3 server runtimes)

---

## Compatibility Matrix

| Database       | Target  | Runtime       | Entry Point            |
| -------------- | ------- | ------------- | ---------------------- |
| dexie          | browser | -             | index.html             |
| sqljs          | browser | -             | index.html             |
| pg             | server  | node          | server.js (http)       |
| pg             | server  | bun           | server.js (Bun.serve)  |
| pg             | server  | deno          | server.js (Deno.serve) |
| mysql2         | server  | node/bun/deno | (same as pg)           |
| better_sqlite3 | server  | node/bun/deno | (same as pg)           |

---

## Success Criteria

1. YAML configuration loads and merges correctly with build options
2. All three runtimes can run server-side builds
3. `node:` prefixed imports work across all runtimes
4. Runtime selection respects priority chain (env > database.yml > ruby2js.yml)
5. Browser builds ignore runtime setting
6. Documentation covers all configuration options and runtime choices
