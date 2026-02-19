# Plan: Split ruby2js-rails into juntos + juntos-dev

## Motivation

`ruby2js-rails` currently bundles three concerns in one package:

1. **Runtime** — database adapters, ActiveRecord-like ORM, relation builder, collection proxy, reference proxy, dialects, drivers, path helpers, ERB/Phlex runtime, deployment targets, RPC client/server
2. **Build tooling** — CLI, standalone transpiler, Vite plugins, dev server, linting, migration generator
3. **Shared transforms** — AST transformation logic used by both build and Vite

This means production deploys pull in `chokidar`, `ws`, `js-yaml`, a 20K-line bundled transpiler, and the entire build CLI. Splitting into two packages gives:

- **`juntos`** — runtime only, ships to production (~10K lines)
- **`juntos-dev`** — build tooling, dev only (~16K lines)

## Package Boundaries

### `juntos` (runtime)

Everything needed at runtime in a deployed application:

```
juntos/
  adapters/
    active_record_base.mjs      (652 lines)
    active_record_sql.mjs       (918 lines)
    relation.mjs                (262 lines)
    collection_proxy.mjs        (240 lines)
    reference.mjs               (90 lines)
    sql_parser.mjs
    inflector.mjs
    dialects/
      sqlite.mjs                (78 lines)
      sqlite_browser.mjs        (141 lines)
      postgres.mjs              (72 lines)
      mysql.mjs                 (74 lines)
    active_record_sqlite.mjs    (216 lines)
    active_record_pg.mjs        (205 lines)
    active_record_mysql2.mjs    (192 lines)
    active_record_neon.mjs      (184 lines)
    active_record_turso.mjs     (184 lines)
    active_record_pglite.mjs    (199 lines)
    active_record_d1.mjs        (170 lines)
    active_record_dexie.mjs     (530 lines)
    active_record_supabase.mjs  (694 lines)
    active_record_rpc.mjs       (458 lines)
    active_record_better_sqlite3.mjs (179 lines)
    active_record_sqljs.mjs     (216 lines)
    active_record_wa_sqlite.mjs (206 lines)
    active_record_sqlite_wasm.mjs (93 lines)
    active_record_planetscale.mjs (168 lines)
  rpc/
    client.mjs
    server.mjs
  targets/
    browser/rails.js
    node/rails.js
    deno/rails.js
    bun/rails.js
    electron/rails.js
    tauri/rails.js
    cloudflare/
    vercel-edge/
    vercel-node/
    capacitor/
  components/
    JsonStreamProvider.js
  rails_base.js
  helpers.js
  path_helper.mjs
  path_helper_browser.mjs
  erb_runtime.mjs
  phlex_runtime.mjs
  url_helpers.mjs
  testing.mjs
  test/
    relation_test.mjs           (existing, expand significantly)
```

**Dependencies:** Minimal — only database drivers as optional/peer deps. No `chokidar`, `js-yaml`, or `ws`.

**Exports:** Designed for clean import paths:
```js
import ActiveRecord from 'juntos/adapters/active_record_sqlite'
import { Relation } from 'juntos/adapters/relation'
import { rails } from 'juntos/targets/node/rails'
```

### `juntos-dev` (build tooling)

Everything needed at development/build time:

```
juntos-dev/
  cli.mjs                      (4,155 lines — juntos CLI)
  build.mjs                    (3,857 lines — standalone builder, refactor to scaffolding only)
  vite.mjs                     (2,489 lines — Vite plugin suite)
  vite-models.mjs              (449 lines)
  vite-ssr-dev.mjs             (104 lines)
  transform.mjs                (2,882 lines — shared AST transforms)
  dev-server.mjs               (413 lines)
  lint.mjs                     (145 lines)
  migrate.mjs                  (241 lines)
  ruby2js.js                   (20,094 lines — bundled transpiler)
  filters/                     (transpiled filter files)
  lib/
    erb_compiler.js
    migration_sql.js
    seed_sql.js
  dist/                        (framework transformers)
    astro_template_compiler.mjs
    svelte_template_compiler.mjs
    vue_template_compiler.mjs
    erb_pnode_transformer.mjs
    ...
```

**Dependencies:** `chokidar`, `js-yaml`, `ws`, `ruby2js` (transpiler), `juntos` (runtime, as peer dep for adapter copying).

## Migration Steps

### Phase 1: Prepare (non-breaking)

1. **Audit all imports** between runtime and tooling files. Verify the boundary is clean — no runtime file imports from build/vite/transform/cli.
2. **Extract shared config** — `load_database_config()` exists in both `build.mjs` and `vite.mjs`. Move to a shared `config.mjs` in the runtime package (config loading is needed at runtime for adapter selection).
3. **Add `toSQL()` to Relation** — enables direct unit testing of query building without executing against a database.

### Phase 2: Create `juntos` package

4. **Create `packages/juntos/`** with its own `package.json`.
5. **Move runtime files** from `packages/ruby2js-rails/` to `packages/juntos/`.
6. **Set up exports map** in `package.json` for clean import paths.
7. **Write unit tests** for the query/relation layer:
   - `toSQL()` output for all supported query patterns
   - WHERE: hash, array, range, not, or, nested table references
   - JOIN: simple, nested hash syntax
   - ORDER, LIMIT, OFFSET
   - Aggregates: count, group/count, maximum, minimum, sum
   - PLUCK: single column, multi-column
   - Existence: exists?, any?
   - CollectionProxy query delegation
8. **Add tarball build** to the release Rakefile.

### Phase 3: Create `juntos-dev` package

9. **Create `packages/juntos-dev/`** with its own `package.json`.
10. **Move tooling files** from `packages/ruby2js-rails/`.
11. **Update imports** to reference `juntos` for runtime pieces.
12. **Refactor `build.mjs`**: Remove duplicate transpilation pipeline. Keep only scaffolding (deployment config generation, package.json generation, adapter/dependency management, migration/seed SQL). Have eject use Vite with `preserveModules` for the actual Ruby→JS transpilation.
13. **Deduplicate config loading** — both `build.mjs` and `vite.mjs` use the shared config from `juntos`.

### Phase 4: Migrate and remove ruby2js-rails

14. **Update demo apps** (blog, chat, notes, showcase) to import from `juntos` and `juntos-dev`.
15. **Update tarball build** in Rakefile — produce `juntos-beta.tgz` and `juntos-dev-beta.tgz` instead of `ruby2js-rails-beta.tgz`.
16. **Delete `packages/ruby2js-rails/`** once all references are migrated.

### Phase 5: Expand runtime (incremental)

With the test suite in place, incrementally add missing query features driven by real app needs (showcase, fizzy):

**Tier 1 — High frequency gaps:**
- `update_all` — bulk updates without loading records
- `transaction` — BEGIN/COMMIT/ROLLBACK with raise-Rollback semantics
- Nested hash joins — `joins(entry: [:lead, :follow])`
- WHERE on joined table columns — `.where(studios: { id: x })`
- `group().count` — returns `{key: count}` hash

**Tier 2 — Medium frequency:**
- `any?` — alias to exists/count
- Multi-column `pluck` — returns arrays of arrays
- Scopes — model-level scope definitions callable on Relation and CollectionProxy
- `pick` — single-value pluck
- CollectionProxy `find_by` and `count`

**Tier 3 — Edge cases:**
- `sole`, `destroy_by`, `find_by!`, `preload`
- Raw SQL fragments in where/order/pluck

## Open Questions

1. **Separate repo or monorepo?** Starting as subdirectories in `packages/` within the ruby2js repo is simplest. Can extract to separate repos later if release cycles diverge significantly.

2. **Name availability.** Both `juntos` and `juntos-dev` are available on npm (verified 2026-02-19). Scoped alternatives `@juntos/runtime` and `@juntos/dev` are also available but require creating the `@juntos` npm org first. Scoped names provide room to grow (`@juntos/cli`, `@juntos/adapters`) if further splits are needed later. For now, publish only as tarballs on ruby2js.com (same as current ruby2js-rails-beta.tgz approach). Register names on npm when ready for public release.

3. **Vite plugin relationship.** `vite-plugin-ruby2js` stays as-is (depends only on `ruby2js` transpiler). `juntos-dev/vite.mjs` is the full Rails integration. These serve different audiences and don't need merging.

4. **`ruby2js-rails` as scaffolding?** During implementation, it may be convenient to keep `packages/ruby2js-rails/` as the working directory and split files out of it into `packages/juntos/` and `packages/juntos-dev/`. Once migration is complete, delete it entirely — it was never published to npm.
