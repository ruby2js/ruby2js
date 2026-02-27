#!/usr/bin/env node

/**
 * Juntos CLI - Rails patterns, JavaScript runtimes
 *
 * Commands:
 *   dev       Start development server with hot reload
 *   build     Build for deployment
 *   eject     Write transpiled JavaScript files to disk
 *   up        Build and run locally
 *   test      Run tests with Vitest
 *   db        Database commands (migrate, seed, prepare, reset, create, drop)
 *   lint      Scan Ruby files for transpilation issues
 *   info      Show current configuration
 *   doctor    Check environment and prerequisites
 */

import { spawn, spawnSync, execSync } from 'child_process';
import { existsSync, readFileSync, writeFileSync, unlinkSync, mkdirSync, chmodSync, readdirSync, copyFileSync, cpSync, statSync } from 'fs';
import { join, basename, dirname, relative } from 'path';
import { fileURLToPath } from 'url';
import { createHash } from 'crypto';
import { crc32 } from 'zlib';

// Import shared transformation logic
import {
  findModels,
  findLeafCollisions,
  modelClassName,
  findMigrations,
  findViewResources,
  findControllers,
  getBuildOptions,
  createMetadata,
  buildAppManifest,
  deriveAssociationMap,
  generateModelsModuleForEject,
  generateMigrationsModuleForEject,
  generateViewsModuleForEject,
  generateTurboStreamModuleForEject,
  generatePackageJsonForEject,
  generateViteConfigForEject,
  generateTestSetupForEject,
  generateTestGlobalsForEject,
  generateTestRunnerForEject,
  generateTestLoaderRegistration,
  generateTestLoaderHooks,
  generateTestVitestShim,
  generateMainJsForEject,
  generateVitestConfigForEject,
  generateBrowserIndexHtml,
  generateBrowserMainJs,
  ensureRuby2jsReady,
  transformRuby,
  transformErb,
  transformJsxRb,
  fixImportsForEject,
  fixTestImportsForEject,
  globToRegex,
  matchesAny,
  shouldIncludeFile,
  lintRuby,
  ErbCompiler
} from './transform.mjs';

import { singularize, camelize, pluralize, underscore } from 'juntos/adapters/inflector.mjs';
import { loadDatabaseConfig as _loadDatabaseConfig, ADAPTER_ALIASES as _ADAPTER_ALIASES } from 'juntos/config.mjs';

// loadConfig is dynamically imported from vite.mjs when needed (in runEject)
// to avoid loading js-yaml at startup, which may not be installed yet

// Try to load js-yaml, fall back to naive parsing if not available
// (js-yaml may not be available when CLI is run standalone from tarball)
let yaml = null;
try {
  yaml = await import('js-yaml');
  yaml = yaml.default || yaml;
} catch {
  // js-yaml not available, will use fallback parser
}

// CLI runs from the app's working directory
const APP_ROOT = process.cwd();

// Debug mode: set DEBUG=1 or JUNTOS_DEBUG=1 for verbose error output
const DEBUG = process.env.DEBUG === '1' || process.env.JUNTOS_DEBUG === '1';

// Path to this package (for migrate.mjs)
const __dirname = dirname(fileURLToPath(import.meta.url));
const MIGRATE_SCRIPT = join(__dirname, 'migrate.mjs');

// Format error for display - includes stack trace in debug mode
function formatError(err) {
  if (DEBUG && err.stack) {
    return err.stack;
  }
  return err.message;
}

/**
 * Load eject configuration from ruby2js.yml.
 *
 * @param {string} appRoot - Application root directory
 * @returns {Object} Eject configuration { include, exclude, output }
 */
function loadEjectConfig(appRoot) {
  const configPath = join(appRoot, 'config/ruby2js.yml');
  if (!existsSync(configPath)) {
    return { include: [], exclude: [], output: null };
  }

  try {
    if (!yaml) {
      return { include: [], exclude: [], output: null };
    }
    const parsed = yaml.load(readFileSync(configPath, 'utf8'));
    const ejectConfig = parsed?.eject || {};
    return {
      include: ejectConfig.include || [],
      exclude: ejectConfig.exclude || [],
      output: ejectConfig.output || null
    };
  } catch (e) {
    console.warn(`Warning: Failed to parse ruby2js.yml: ${e.message}`);
    return { include: [], exclude: [], output: null };
  }
}

// ============================================
// File finding helpers
// ============================================

/**
 * Recursively find Ruby model files (*.rb) in a directory.
 * Returns relative paths like 'account.rb' or 'account/export.rb'.
 */
function findRubyModelFiles(dir) {
  const files = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (entry.isDirectory()) {
      // Skip concerns directory - those are handled separately via mixins
      if (entry.name === 'concerns') continue;
      const subFiles = findRubyModelFiles(join(dir, entry.name));
      files.push(...subFiles.map(f => join(entry.name, f)));
    } else if (entry.name.endsWith('.rb') && !entry.name.startsWith('._')) {
      files.push(entry.name);
    }
  }
  return files;
}

// ============================================
// Test file transpilation helpers
// ============================================

/**
 * Recursively find Ruby test files (*_test.rb) in a directory.
 */
function findRubyTestFiles(dir) {
  const files = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (entry.isDirectory()) {
      const subFiles = findRubyTestFiles(join(dir, entry.name));
      files.push(...subFiles.map(f => join(entry.name, f)));
    } else if (entry.name.endsWith('_test.rb') && !entry.name.startsWith('._')) {
      files.push(entry.name);
    }
  }
  return files;
}

/**
 * Generate a deterministic UUID v5 from a fixture label, matching Rails'
 * ActiveRecord::FixtureSet.identify(label, :uuid).
 * Uses the OID namespace (6ba7b812-9dad-11d1-80b4-00c04fd430c8) per Rails source.
 */
function fixtureIdentifyUUID(label) {
  // OID namespace UUID as bytes
  const ns = Buffer.from('6ba7b8129dad11d180b400c04fd430c8', 'hex');
  const name = Buffer.from(String(label), 'utf-8');
  const hash = createHash('sha1').update(Buffer.concat([ns, name])).digest();

  // Set version 5 (byte 6 high nibble)
  hash[6] = (hash[6] & 0x0f) | 0x50;
  // Set variant RFC 4122 (byte 8 high bits = 10)
  hash[8] = (hash[8] & 0x3f) | 0x80;

  const hex = hash.toString('hex');
  return `${hex.slice(0,8)}-${hex.slice(8,12)}-${hex.slice(12,16)}-${hex.slice(16,20)}-${hex.slice(20,32)}`;
}

/**
 * Generate a deterministic integer from a fixture label, matching Rails'
 * ActiveRecord::FixtureSet.identify(label).
 * Uses CRC32 modulo MAX_ID (2^30-1) per Rails source.
 */
function fixtureIdentifyInteger(label) {
  const MAX_ID = 2 ** 30 - 1;
  return (crc32(Buffer.from(String(label))) >>> 0) % MAX_ID;
}

/**
 * Resolve a fixture reference value, stripping the _uuid suffix used by
 * Rails' UUID fixture convention. E.g., "writebook_uuid" -> "writebook".
 * Returns { fixtureName, isUuid } or null if not resolvable.
 */
function resolveFixtureRef(value, targetTable, fixtures) {
  // Direct match
  if (fixtures[targetTable]?.[value]) {
    return { fixtureName: value, isUuid: false };
  }
  // Strip _uuid suffix (Rails convention for UUID FK references)
  if (value.endsWith('_uuid')) {
    const stripped = value.slice(0, -5);
    if (fixtures[targetTable]?.[stripped]) {
      return { fixtureName: stripped, isUuid: true };
    }
  }
  return null;
}

/**
 * Parse a polymorphic fixture reference: "37s_uuid (Account)" -> { fixtureRef: "37s_uuid", typeName: "Account", table: "accounts" }
 * Returns null if the value doesn't match the polymorphic pattern.
 */
function parsePolymorphicRef(value) {
  const match = value.match(/^(\S+)\s+\((\w+)\)$/);
  if (!match) return null;
  const [, fixtureRef, typeName] = match;
  // Convert TypeName to table_name: Account -> accounts, BoardColumn -> board_columns
  const underscored = typeName.replace(/([A-Z])/g, (m, c, i) => (i > 0 ? '_' : '') + c.toLowerCase());
  return { fixtureRef, typeName, table: pluralize(underscored) };
}

/**
 * Try to resolve a fixture value, handling both normal and polymorphic references.
 * For polymorphic values like "37s_uuid (Account)", derives the target table from the type.
 * Returns { ref, targetTable } or null.
 */
function resolveFixtureValue(value, col, table, associationMap, fixtures) {
  // Try polymorphic first: "37s_uuid (Account)"
  const poly = parsePolymorphicRef(value);
  if (poly) {
    const ref = resolveFixtureRef(poly.fixtureRef, poly.table, fixtures);
    if (ref) return { ref, targetTable: poly.table };
  }
  // Try normal association resolution
  const targetTable = inferTargetTable(col, table, associationMap, fixtures);
  if (targetTable) {
    const ref = resolveFixtureRef(value, targetTable, fixtures);
    if (ref) return { ref, targetTable };
  }
  return null;
}

/**
 * Parse all fixture YAML files from test/fixtures/.
 * Returns a map: { table_name: { fixture_name: { column: value, ... }, ... }, ... }
 */
function parseFixtureFiles(appRoot) {
  const fixturesDir = join(appRoot, 'test/fixtures');
  if (!existsSync(fixturesDir)) return {};
  if (!yaml) return {};

  const fixtures = {};
  const fixtureFiles = readdirSync(fixturesDir)
    .filter(f => f.endsWith('.yml') && !f.startsWith('._'));

  for (const file of fixtureFiles) {
    const tableName = file.replace('.yml', '');
    try {
      let content = readFileSync(join(fixturesDir, file), 'utf-8');
      // Evaluate ActiveRecord::FixtureSet.identify() calls before generic ERB strip
      content = content.replace(/<%=\s*ActiveRecord::FixtureSet\.identify\(["']([^"']+)["'],\s*:uuid\)\s*%>/g,
        (m, label) => fixtureIdentifyUUID(label));
      content = content.replace(/<%=\s*ActiveRecord::FixtureSet\.identify\(["']([^"']+)["']\)\s*%>/g,
        (m, label) => fixtureIdentifyInteger(label));
      // Handle simple ERB expressions (e.g., <%= Date.current.iso8601 %>)
      content = content.replace(/<%=\s*Date\.current\.iso8601\s*%>/g, new Date().toISOString().split('T')[0]);
      content = content.replace(/<%=\s*Date\.today\.iso8601\s*%>/g, new Date().toISOString().split('T')[0]);
      content = content.replace(/<%=\s*Time\.now\.iso8601\s*%>/g, new Date().toISOString());
      // Remove remaining ERB tags (best-effort)
      content = content.replace(/<%.*?%>/g, '""');

      const parsed = yaml.load(content);
      if (parsed && typeof parsed === 'object') {
        fixtures[tableName] = parsed;
      }
    } catch (err) {
      if (DEBUG) {
        console.warn(`    Warning: Failed to parse fixture ${file}: ${err.message}`);
      }
    }
  }
  return fixtures;
}

/**
 * Build an association map from transpiled model files.
 * Reads .associations = {...} from each model file.
 * Returns: { table_name: { assoc_name: target_table, ... }, ... }
 */
function buildAssociationMap(modelsDir) {
  const assocMap = {};
  if (!existsSync(modelsDir)) return assocMap;

  const modelFiles = readdirSync(modelsDir)
    .filter(f => f.endsWith('.js') && f !== 'index.js' && f !== 'application_record.js');

  for (const file of modelFiles) {
    try {
      const content = readFileSync(join(modelsDir, file), 'utf-8');

      // Extract class name
      const classMatch = content.match(/(?:export\s+)?class\s+(\w+)/);
      if (!classMatch) continue;
      const className = classMatch[1];

      // Find the associations object literal by locating the marker and
      // extracting the balanced braces that follow it
      const markers = ['static associations = ', `${className}.associations = `];
      let assocObj = null;

      for (const marker of markers) {
        const idx = content.indexOf(marker);
        if (idx === -1) continue;

        const braceStart = content.indexOf('{', idx + marker.length);
        if (braceStart === -1) continue;

        // Walk forward counting braces to find the matching close
        let depth = 0;
        let end = -1;
        for (let i = braceStart; i < content.length; i++) {
          if (content[i] === '{') depth++;
          else if (content[i] === '}') { depth--; if (depth === 0) { end = i; break; } }
        }
        if (end === -1) continue;

        const literal = content.slice(braceStart, end + 1);
        try {
          assocObj = new Function('return ' + literal)();
        } catch { /* skip malformed */ }
        if (assocObj) break;
      }

      if (assocObj) {
        const tableName = underscore(pluralize(className));
        const tableAssocs = {};
        for (const [assocName, meta] of Object.entries(assocObj)) {
          if (meta && meta.model) {
            // Handle namespaced models: "Card::NotNow" → "card_not_nows"
            const modelParts = meta.model.split('::');
            const leafName = modelParts.pop();
            const prefix = modelParts.map(p => underscore(p)).join('_');
            const tableName2 = prefix ? `${prefix}_${underscore(pluralize(leafName))}` : underscore(pluralize(leafName));
            tableAssocs[assocName] = {
              table: tableName2,
              type: meta.type || 'belongs_to'
            };
          }
        }
        if (Object.keys(tableAssocs).length > 0) {
          assocMap[tableName] = tableAssocs;
        }
      }
    } catch (err) {
      // Skip files that can't be read
    }
  }
  return assocMap;
}

/**
 * Infer the target table for a fixture column.
 * First checks the association map, then falls back to Rails convention:
 * if pluralize(col) exists as a fixture table, treat col as a FK reference.
 * This handles cases like `column: writebook_triage_uuid` where there's no
 * explicit belongs_to but the DB has a column_id FK.
 */
function inferTargetTable(col, table, associationMap, fixtures) {
  // Check explicit association map first
  const assocEntry = (associationMap[table] || {})[col];
  if (assocEntry) return assocEntry.table || assocEntry;

  // Convention-based: pluralize the column name and check if that table exists in fixtures
  if (!col.endsWith('_id') && col !== 'id') {
    const conventionTable = pluralize(col);
    if (fixtures[conventionTable]) return conventionTable;
  }
  return null;
}

/**
 * Build dependency graph from fixtures and topologically sort tables.
 * Returns ordered array of table names.
 */
function topologicalSortTables(referencedTables, fixtures, associationMap) {
  const deps = {};  // table -> Set of tables it depends on
  for (const table of referencedTables) {
    deps[table] = new Set();
    const tableAssocs = associationMap[table] || {};
    const tableFixtures = fixtures[table] || {};

    for (const fixtureName of Object.keys(tableFixtures)) {
      const fixtureData = tableFixtures[fixtureName];
      if (!fixtureData || typeof fixtureData !== 'object') continue;

      for (const [col, value] of Object.entries(fixtureData)) {
        // Check if this column is a foreign key reference
        if (col.endsWith('_id') && typeof value === 'number') {
          // Explicit ID - no dependency
          continue;
        }
        if (typeof value !== 'string') continue;
        // Check if column matches an association (explicit, convention, or polymorphic)
        const resolved = resolveFixtureValue(value, col, table, associationMap, fixtures);
        if (resolved && referencedTables.has(resolved.targetTable)) {
          deps[table].add(resolved.targetTable);
        }
      }
    }
  }

  // Topological sort (Kahn's algorithm)
  // inDegree[A] = number of tables A depends on (must be created first)
  const sorted = [];
  const indeg = {};
  for (const table of referencedTables) {
    indeg[table] = deps[table]?.size || 0;
  }

  const queue = [];
  for (const table of referencedTables) {
    if (indeg[table] === 0) queue.push(table);
  }

  while (queue.length > 0) {
    const table = queue.shift();
    sorted.push(table);
    // Find tables that depend on this one and decrement their in-degree
    for (const [other, otherDeps] of Object.entries(deps)) {
      if (otherDeps.has(table)) {
        indeg[other]--;
        if (indeg[other] === 0) {
          queue.push(other);
        }
      }
    }
  }

  // If there are remaining tables (cycle), append them
  for (const table of referencedTables) {
    if (!sorted.includes(table)) {
      sorted.push(table);
    }
  }

  return sorted;
}

/**
 * Build a fixture plan from Ruby source, suitable for passing to the test
 * filter via metadata. The test filter then generates the fixture setup code
 * at AST level (correct source maps) instead of text-level post-processing.
 *
 * Returns { setupCode, replacements } or null if no fixtures are referenced.
 * - setupCode: JavaScript string for the beforeEach block (let _fixtures = {}; beforeEach(...))
 * - replacements: { "table:fixture": "table_fixture", ... } for AST-level fixture ref replacement
 */
function buildFixturePlan(rubySource, fixtures, associationMap, { loadAll = false } = {}) {
  // Find fixture references in Ruby source: cards(:logo), sessions(:david), accounts(:"37s"), accounts("37s")
  const fixtureCallRegex = /\b([a-z_]+)\s*(?:[\(:]\s*:["']?(\w+)["']?|\("(\w+)"\))/g;
  const referencedFixtures = new Map();
  let match;

  while ((match = fixtureCallRegex.exec(rubySource)) !== null) {
    const tableName = match[1];
    const fixtureName = match[2] || match[3];
    if (fixtures[tableName] && fixtures[tableName][fixtureName]) {
      const key = `${tableName}_${fixtureName}`;
      referencedFixtures.set(key, { table: tableName, fixture: fixtureName });
    }
  }

  if (referencedFixtures.size === 0) {
    if (!loadAll) return null;

    // Load all fixtures (for system tests, matching Rails behavior)
    for (const [tableName, tableFixtures] of Object.entries(fixtures)) {
      for (const [fixtureName, fixtureData] of Object.entries(tableFixtures)) {
        if (!fixtureData || typeof fixtureData !== 'object') continue;
        const key = `${tableName}_${fixtureName}`;
        referencedFixtures.set(key, { table: tableName, fixture: fixtureName });
      }
    }

    if (referencedFixtures.size === 0) return null;
  }

  // Resolve transitive dependencies (same logic as inlineFixtures)
  const allFixtures = new Map(referencedFixtures);
  const toResolve = [...referencedFixtures.values()];
  while (toResolve.length > 0) {
    const { table, fixture } = toResolve.pop();
    const fixtureData = fixtures[table]?.[fixture];
    if (!fixtureData || typeof fixtureData !== 'object') continue;

    for (const [col, value] of Object.entries(fixtureData)) {
      if (typeof value !== 'string') continue;
      const resolved = resolveFixtureValue(value, col, table, associationMap, fixtures);
      if (resolved) {
        const { ref, targetTable } = resolved;
        const depKey = `${targetTable}_${ref.fixtureName}`;
        if (!allFixtures.has(depKey)) {
          allFixtures.set(depKey, { table: targetTable, fixture: ref.fixtureName });
          toResolve.push({ table: targetTable, fixture: ref.fixtureName });
        }
      }
    }
  }

  // Reverse resolution: pull in fixtures that reference collected fixtures via FK.
  // Scans all fixture tables for entries whose FK columns point to collected fixtures.
  // This handles has_many, has_one, and any other reverse FK relationship — matching
  // Rails behavior where all fixtures are loaded into the DB before each test.
  const collectedByTable = new Map();
  for (const { table, fixture } of allFixtures.values()) {
    if (!collectedByTable.has(table)) collectedByTable.set(table, new Set());
    collectedByTable.get(table).add(fixture);
  }

  const reverseBackRefs = [];
  let foundNew = true;

  while (foundNew) {
    foundNew = false;

    for (const [childTable, childTableFixtures] of Object.entries(fixtures)) {
      for (const [childFixtureName, childFixtureData] of Object.entries(childTableFixtures)) {
        if (!childFixtureData || typeof childFixtureData !== 'object') continue;
        const childKey = `${childTable}_${childFixtureName}`;
        if (allFixtures.has(childKey)) continue;

        for (const [col, value] of Object.entries(childFixtureData)) {
          if (typeof value !== 'string') continue;
          const targetTable = inferTargetTable(col, childTable, associationMap, fixtures);
          if (!targetTable) continue;
          const parentFixtures = collectedByTable.get(targetTable);
          if (!parentFixtures) continue;

          const ref = resolveFixtureRef(value, targetTable, fixtures);
          if (ref && parentFixtures.has(ref.fixtureName)) {
            allFixtures.set(childKey, { table: childTable, fixture: childFixtureName });
            if (!collectedByTable.has(childTable)) collectedByTable.set(childTable, new Set());
            collectedByTable.get(childTable).add(childFixtureName);
            foundNew = true;

            // Resolve forward dependencies of the newly added fixture
            for (const [fwdCol, fwdVal] of Object.entries(childFixtureData)) {
              if (typeof fwdVal !== 'string') continue;
              const resolved = resolveFixtureValue(fwdVal, fwdCol, childTable, associationMap, fixtures);
              if (resolved) {
                const depKey = `${resolved.targetTable}_${resolved.ref.fixtureName}`;
                if (!allFixtures.has(depKey)) {
                  allFixtures.set(depKey, { table: resolved.targetTable, fixture: resolved.ref.fixtureName });
                  if (!collectedByTable.has(resolved.targetTable)) collectedByTable.set(resolved.targetTable, new Set());
                  collectedByTable.get(resolved.targetTable).add(resolved.ref.fixtureName);
                }
              }
            }
            break;
          }
        }
      }
    }
  }

  // Build has_one back-reference assignments from association map
  for (const [modelTable, assocs] of Object.entries(associationMap)) {
    for (const [assocName, assocEntry] of Object.entries(assocs)) {
      if (!assocEntry || assocEntry.type !== 'has_one') continue;
      const reverseTable = assocEntry.table;
      if (!reverseTable || !fixtures[reverseTable]) continue;

      const collectedNames = collectedByTable.get(modelTable);
      if (!collectedNames) continue;

      const fkCol = singularize(modelTable);

      for (const [revFixtureName, revFixtureData] of Object.entries(fixtures[reverseTable])) {
        if (!revFixtureData || typeof revFixtureData !== 'object') continue;
        const fkValue = revFixtureData[fkCol];
        if (typeof fkValue !== 'string') continue;

        const ref = resolveFixtureRef(fkValue, modelTable, fixtures);
        if (ref && collectedNames.has(ref.fixtureName)) {
          const childKey = `${reverseTable}_${revFixtureName}`;
          const parentKey = `${modelTable}_${ref.fixtureName}`;
          if (allFixtures.has(parentKey) && allFixtures.has(childKey)) {
            reverseBackRefs.push({ parentKey, assocName, childKey });
          }
        }
      }
    }
  }

  // Sort tables by dependency
  const referencedTables = new Set([...allFixtures.values()].map(f => f.table));
  const sortedTables = topologicalSortTables(referencedTables, fixtures, associationMap);

  // Generate fixture creation lines (same text as inlineFixtures)
  const createLines = [];

  for (const table of sortedTables) {
    const tableFixtures = [...allFixtures.values()].filter(f => f.table === table);
    for (const { fixture } of tableFixtures) {
      const fixtureData = fixtures[table]?.[fixture];
      if (!fixtureData || typeof fixtureData !== 'object') continue;

      const key = `${table}_${fixture}`;
      const modelName = camelize(singularize(table));

      const attrs = [];
      for (const [col, value] of Object.entries(fixtureData)) {
        if (typeof value === 'string') {
          const resolved = resolveFixtureValue(value, col, table, associationMap, fixtures);
          if (resolved) {
            const { ref, targetTable } = resolved;
            if (allFixtures.has(`${targetTable}_${ref.fixtureName}`)) {
              attrs.push(`${col}: _fixtures.${targetTable}_${ref.fixtureName}`);
            } else {
              attrs.push(`${col}_id: ${JSON.stringify(fixtureIdentifyUUID(ref.fixtureName))}`);
            }
            continue;
          }
        }
        attrs.push(`${col}: ${JSON.stringify(value)}`);
      }

      createLines.push(`  _fixtures.${key} = await ${modelName}.create({${attrs.join(', ')}});`);
    }
  }

  // Add back-reference assignments
  for (const { parentKey, assocName, childKey } of reverseBackRefs) {
    if (allFixtures.has(parentKey) && allFixtures.has(childKey)) {
      createLines.push(`  _fixtures.${parentKey}.${assocName} = _fixtures.${childKey};`);
    }
  }

  if (createLines.length === 0) return null;

  // Build replacements map: "table:fixture" -> "table_fixture"
  const replacements = {};
  for (const [key, { table, fixture }] of allFixtures) {
    replacements[`${table}:${fixture}`] = key;
  }

  // Wrap fixture inserts with deferred FK checks (like Rails' disable_referential_integrity)
  const firstModel = camelize(singularize(sortedTables[0]));
  const deferLine = `  if (${firstModel}._deferForeignKeys) ${firstModel}._deferForeignKeys(true);`;
  const undeferLine = `  if (${firstModel}._deferForeignKeys) ${firstModel}._deferForeignKeys(false);`;
  const setupCode = `beforeEach(async () => {\n${deferLine}\n${createLines.join('\n')}\n${undeferLine}\n});`;

  // Collect unique model names referenced in fixture creates (for import generation)
  const fixtureModels = [...new Set([...allFixtures.values()].map(f => camelize(singularize(f.table))))];

  return { setupCode, replacements, fixtureModels };
}

/**
 * Post-process a transpiled Ruby module into individual named exports.
 * The Ruby module converter produces `const ModuleName = { method1(...) {...}, ... }`.
 * This extracts each method as `export async function methodName(...) { ... }`.
 * Also adds `import { fixtures }` when the code references `fixtures`.
 *
 * @param {string} code - Transpiled JavaScript from a Ruby module
 * @param {string[]} modelNames - Known AR model class names (for async detection)
 * @returns {{ code: string, exports: string[] }} - Processed code and list of exported names
 */
function postProcessTestHelper(code, modelNames = []) {
  const exportedNames = [];

  // Match: [export] const ModuleName = { ... }  (the entire object literal)
  const moduleMatch = code.match(/^(?:export\s+)?const \w+ = \{([\s\S]*)\}\s*$/);
  if (!moduleMatch) {
    // Not a module object literal — return as-is
    return { code, exports: exportedNames };
  }

  const body = moduleMatch[1];

  // Build regex for AR model calls that need await
  const arMethods = ['findBy', 'find', 'create', 'update', 'destroy', 'where',
    'all', 'first', 'last', 'count', 'deleteAll', 'destroyAll', 'findOrCreateBy',
    'save', 'reload', 'order', 'limit', 'pluck', 'exists'];
  const modelPattern = modelNames.length > 0
    ? new RegExp(`(?:(?:${modelNames.join('|')})\\.(?:${arMethods.join('|')})\\b|(?:await\\s))`)
    : /await\s/;

  // Parse methods from the object literal body.
  // Methods appear as: methodName(...) { ... },  or  get methodName(...) { ... },
  // We use a brace-balanced parser to extract each method.
  const functions = [];
  let i = 0;
  while (i < body.length) {
    // Skip whitespace and commas
    while (i < body.length && /[\s,]/.test(body[i])) i++;
    if (i >= body.length) break;

    // Match method signature: optional "get " prefix, name, params
    const sigMatch = body.slice(i).match(/^(?:get\s+)?(\w+)\(([^)]*)\)\s*\{/);
    if (!sigMatch) {
      // Skip unrecognized content
      i++;
      continue;
    }

    const methodName = sigMatch[1];
    let params = sigMatch[2];
    const braceStart = i + sigMatch[0].length - 1;

    // Find matching close brace
    let depth = 0;
    let end = -1;
    for (let j = braceStart; j < body.length; j++) {
      if (body[j] === '{') depth++;
      else if (body[j] === '}') {
        depth--;
        if (depth === 0) { end = j; break; }
      }
    }
    if (end === -1) break;

    let methodBody = body.slice(braceStart + 1, end);

    // Remove _implicitBlockYield from params — convert to fn callback param
    const hasYield = params.includes('_implicitBlockYield');
    if (hasYield) {
      params = params.replace(/,?\s*_implicitBlockYield\s*=\s*null/, '').trim();
      if (params.length > 0 && !params.endsWith(',')) {
        params += ', fn';
      } else {
        params += params.length > 0 ? ' fn' : 'fn';
      }
      // Replace _implicitBlockYield() calls with fn()
      methodBody = methodBody.replace(/_implicitBlockYield\(\)/g, 'fn()');
    }

    // Clean up: remove leading `return` on last statement if it's an assignment
    methodBody = methodBody.replace(/\n(\s*)return (Current\.\w+ = )/, '\n$1$2');

    functions.push({ name: methodName, params, body: methodBody });
    exportedNames.push(methodName);

    i = end + 1;
  }

  if (functions.length === 0) {
    return { code, exports: exportedNames };
  }

  // Build set of method names for this.X() → X() rewriting
  const methodNames = new Set(functions.map(f => f.name));

  // First pass: determine which methods need async (AR calls or await)
  const asyncMethods = new Set();
  for (const fn of functions) {
    if (modelPattern.test(fn.body)) asyncMethods.add(fn.name);
  }

  // Rewrite this.X(...) → X(...) or await X(...), and propagate async
  let changed = true;
  while (changed) {
    changed = false;
    for (const fn of functions) {
      const rewritten = fn.body.replace(
        /\bthis\.(\w+)\(/g,
        (match, name) => {
          if (!methodNames.has(name)) return match;
          return asyncMethods.has(name) ? `await ${name}(` : `${name}(`;
        }
      );
      if (rewritten !== fn.body) {
        fn.body = rewritten;
        // If we added an await, this method needs to be async too
        if (/\bawait\s/.test(fn.body) && !asyncMethods.has(fn.name)) {
          asyncMethods.add(fn.name);
          changed = true; // propagate: another method calling this one may need async
        }
      }
    }
  }

  // Build output: fixtures import (if referenced) + functions
  const lines = [];
  if (code.includes('fixtures[') || code.includes('fixtures.')) {
    lines.push("import { fixtures } from '../fixtures.mjs';");
    lines.push('');
  }
  lines.push(functions.map(fn => {
    const asyncPrefix = asyncMethods.has(fn.name) ? 'async ' : '';
    return `export ${asyncPrefix}function ${fn.name}(${fn.params}) {${fn.body}}`;
  }).join('\n\n'));
  lines.push('');

  return { code: lines.join('\n'), exports: exportedNames };
}

/**
 * Build a universal replacements map from ALL fixtures (not per-file).
 * Returns { "accounts:37s": "accounts_37s", "cards:logo": "cards_logo", ... }
 */
function buildUniversalReplacementsMap(fixtures) {
  const replacements = {};
  for (const [table, tableFixtures] of Object.entries(fixtures)) {
    if (!tableFixtures || typeof tableFixtures !== 'object') continue;
    for (const fixtureName of Object.keys(tableFixtures)) {
      replacements[`${table}:${fixtureName}`] = `${table}_${fixtureName}`;
    }
  }
  return replacements;
}

/**
 * Generate a shared ESM module (test/fixtures.mjs) that creates all fixtures.
 * This replaces per-file fixture setup with a single shared module that any
 * test file can import.
 *
 * @param {Object} fixtures - Parsed fixture data from parseFixtureFiles()
 * @param {Object} associationMap - Association map from buildAssociationMap()
 * @param {Array} currentAttributes - Current attribute assignments from parseCurrentAttributes()
 * @param {string} modelsDir - Path to transpiled models directory (for filtering)
 * @returns {string} JavaScript module source code
 */
function generateFixturesModule(fixtures, associationMap, currentAttributes, modelsDir) {
  // Determine which model files actually exist (skip join tables without models)
  const existingModelFiles = new Set();
  if (existsSync(modelsDir)) {
    for (const f of readdirSync(modelsDir)) {
      if (f.endsWith('.js') && f !== 'index.js' && f !== 'application_record.js') {
        existingModelFiles.add(f.replace('.js', ''));
      }
    }
  }

  // Collect all tables and their fixtures, skipping tables without model files
  const allFixtures = new Map();
  for (const [table, tableFixtures] of Object.entries(fixtures)) {
    if (!tableFixtures || typeof tableFixtures !== 'object') continue;
    // Check if a model file exists for this table
    const modelFileName = underscore(singularize(table));
    if (!existingModelFiles.has(modelFileName)) {
      if (DEBUG) console.warn(`    Skipping fixtures for ${table}: no model file ${modelFileName}.js`);
      continue;
    }
    for (const fixtureName of Object.keys(tableFixtures)) {
      const key = `${table}_${fixtureName}`;
      allFixtures.set(key, { table, fixture: fixtureName });
    }
  }

  if (allFixtures.size === 0) return '';

  // Sort tables by dependency
  const referencedTables = new Set([...allFixtures.values()].map(f => f.table));
  const sortedTables = topologicalSortTables(referencedTables, fixtures, associationMap);

  // Collect unique model names for imports
  const modelNames = new Set();
  for (const table of sortedTables) {
    modelNames.add(camelize(singularize(table)));
  }

  // Build has_one back-reference assignments
  const reverseBackRefs = [];
  for (const [modelTable, assocs] of Object.entries(associationMap)) {
    for (const [assocName, assocEntry] of Object.entries(assocs)) {
      if (!assocEntry || assocEntry.type !== 'has_one') continue;
      const reverseTable = assocEntry.table;
      if (!reverseTable || !fixtures[reverseTable]) continue;
      if (!referencedTables.has(modelTable) || !referencedTables.has(reverseTable)) continue;

      const fkCol = singularize(modelTable);
      for (const [revFixtureName, revFixtureData] of Object.entries(fixtures[reverseTable])) {
        if (!revFixtureData || typeof revFixtureData !== 'object') continue;
        const fkValue = revFixtureData[fkCol];
        if (typeof fkValue !== 'string') continue;

        const ref = resolveFixtureRef(fkValue, modelTable, fixtures);
        if (ref) {
          const parentKey = `${modelTable}_${ref.fixtureName}`;
          const childKey = `${reverseTable}_${revFixtureName}`;
          if (allFixtures.has(parentKey) && allFixtures.has(childKey)) {
            reverseBackRefs.push({ parentKey, assocName, childKey });
          }
        }
      }
    }
  }

  // Generate model imports
  const importLines = [];
  for (const name of [...modelNames].sort()) {
    const fileName = underscore(name) + '.js';
    importLines.push(`import { ${name} } from '../app/models/${fileName}';`);
  }

  // Generate fixture creation lines
  const createLines = [];
  for (const table of sortedTables) {
    const tableFixtures = [...allFixtures.values()].filter(f => f.table === table);
    for (const { fixture } of tableFixtures) {
      const fixtureData = fixtures[table]?.[fixture];
      if (!fixtureData || typeof fixtureData !== 'object') continue;

      const key = `${table}_${fixture}`;
      const modelName = camelize(singularize(table));

      const attrs = [];
      for (const [col, value] of Object.entries(fixtureData)) {
        if (typeof value === 'string') {
          const resolved = resolveFixtureValue(value, col, table, associationMap, fixtures);
          if (resolved) {
            const { ref, targetTable } = resolved;
            if (allFixtures.has(`${targetTable}_${ref.fixtureName}`)) {
              attrs.push(`${col}: fixtures.${targetTable}_${ref.fixtureName}`);
            } else {
              attrs.push(`${col}_id: ${JSON.stringify(fixtureIdentifyUUID(ref.fixtureName))}`);
            }
            continue;
          }
        }
        attrs.push(`${col}: ${JSON.stringify(value)}`);
      }

      createLines.push(`  fixtures.${key} = await ${modelName}.create({${attrs.join(', ')}});`);
    }
  }

  // Add back-reference assignments
  for (const { parentKey, assocName, childKey } of reverseBackRefs) {
    createLines.push(`  fixtures.${parentKey}.${assocName} = fixtures.${childKey};`);
  }

  // Generate Current attribute assignments
  const currentLines = [];
  if (currentAttributes && currentAttributes.length > 0) {
    for (const { attr, table, fixture } of currentAttributes) {
      const varName = `${table}_${fixture}`;
      currentLines.push(`  Current.${attr} = fixtures.${varName};`);
    }
    currentLines.push(`  await Current.settle();`);
  }

  // Assemble module
  const lines = [
    ...importLines,
    '',
    'export const fixtures = {};',
    '',
    'export async function loadFixtures() {',
    '  for (const key of Object.keys(fixtures)) delete fixtures[key];',
    '',
    ...createLines,
  ];

  if (currentLines.length > 0) {
    lines.push('', ...currentLines);
  }

  lines.push('}', '');

  return lines.join('\n');
}

// ============================================
// Dev-mode test transpilation (for juntos test)
// ============================================


/**
 * Add model imports using virtual modules (for dev-mode tests).
 * Uses 'juntos:models' virtual module instead of concrete file paths.
 */
// Import generation is now handled at the AST level by the test filter
// (lib/ruby2js/filter/rails/test.rb - build_test_imports method).
// The filter reads metadata.import_mode and metadata.models to generate
// s(:import, ...) nodes with correct paths for eject vs. virtual mode.

/**
 * Transpile Ruby test files to .test.mjs for Vitest consumption.
 * Called by `juntos test` before running vitest.
 * Writes .test.mjs files alongside the .rb source files.
 */
async function transpileTestFiles(appRoot, config) {
  const testDir = join(appRoot, 'test');
  if (!existsSync(testDir)) return;

  // Check if there are any Ruby test files
  const modelTestDir = join(testDir, 'models');
  const controllerTestDir = join(testDir, 'controllers');
  const systemTestDir = join(testDir, 'system');
  const hasModelTests = existsSync(modelTestDir) && findRubyTestFiles(modelTestDir).length > 0;
  const hasControllerTests = existsSync(controllerTestDir) && findRubyTestFiles(controllerTestDir).length > 0;
  const hasSystemTests = existsSync(systemTestDir) && findRubyTestFiles(systemTestDir).length > 0;
  if (!hasModelTests && !hasControllerTests && !hasSystemTests) return;

  // Pre-analyze all models to populate metadata with associations, scopes, etc.
  // This replaces the regex-based buildAssociationMapFromRuby with actual
  // model transforms, giving the test filter accurate async/sync decisions.
  const { metadata } = await buildAppManifest(appRoot, config, { mode: 'virtual' });

  // Derive association map from metadata for buildFixturePlan compatibility
  const associationMap = deriveAssociationMap(metadata);

  // Parse fixture YAML files
  const fixtures = parseFixtureFiles(appRoot);

  // Build shared fixture plan (all fixtures, loaded once in beforeAll)
  const hasFixtures = Object.keys(fixtures).length > 0;
  const fullPlan = hasFixtures
    ? buildFixturePlan('', fixtures, associationMap, { loadAll: true })
    : null;

  // Shared plan for test files: replacements only, no setupCode
  // (fixtures are loaded globally via __fixtures.mjs, not per-file)
  const sharedPlan = fullPlan
    ? { replacements: fullPlan.replacements, fixtureModels: fullPlan.fixtureModels }
    : null;

  let count = 0;

  // Transpile model tests
  if (hasModelTests) {
    for (const file of findRubyTestFiles(modelTestDir)) {
      const outName = file.replace(/_test\.rb$/, '.test.mjs');
      const outPath = join(modelTestDir, outName);

      // Skip if .test.mjs is newer than _test.rb
      if (existsSync(outPath)) {
        const rbStat = statSync(join(modelTestDir, file));
        const mjsStat = statSync(outPath);
        if (mjsStat.mtimeMs > rbStat.mtimeMs) continue;
      }

      try {
        const source = readFileSync(join(modelTestDir, file), 'utf-8');
        metadata.fixture_plan = sharedPlan;
        const result = await transformRuby(source, join(modelTestDir, file), 'test', config, appRoot, metadata);
        let code = result.code;

        // Skip empty test suites (no test() calls)
        if (!/\btest\s*\(/.test(code)) {
          if (existsSync(outPath)) unlinkSync(outPath);
          continue;
        }

        writeFileSync(outPath, code);
        count++;
      } catch (err) {
        console.warn(`  Warning: Failed to transpile ${file}: ${err.message}`);
      }
    }
  }

  // Transpile controller tests
  if (hasControllerTests) {
    for (const file of findRubyTestFiles(controllerTestDir)) {
      const outName = file.replace(/_test\.rb$/, '.test.mjs');
      const outPath = join(controllerTestDir, outName);

      // Skip if .test.mjs is newer than _test.rb
      if (existsSync(outPath)) {
        const rbStat = statSync(join(controllerTestDir, file));
        const mjsStat = statSync(outPath);
        if (mjsStat.mtimeMs > rbStat.mtimeMs) continue;
      }

      try {
        const source = readFileSync(join(controllerTestDir, file), 'utf-8');
        metadata.fixture_plan = sharedPlan;
        const result = await transformRuby(source, join(controllerTestDir, file), 'test', config, appRoot, metadata);
        let code = result.code;

        // Skip empty test suites (no test() calls)
        if (!/\btest\s*\(/.test(code)) {
          if (existsSync(outPath)) unlinkSync(outPath);
          continue;
        }

        writeFileSync(outPath, code);
        count++;
      } catch (err) {
        console.warn(`  Warning: Failed to transpile ${file}: ${err.message}`);
      }
    }
  }

  // Transpile system tests
  if (hasSystemTests) {
    for (const file of findRubyTestFiles(systemTestDir)) {
      const outName = file.replace(/_test\.rb$/, '.test.mjs');
      const outPath = join(systemTestDir, outName);

      // Skip if .test.mjs is newer than _test.rb
      if (existsSync(outPath)) {
        const rbStat = statSync(join(systemTestDir, file));
        const mjsStat = statSync(outPath);
        if (mjsStat.mtimeMs > rbStat.mtimeMs) continue;
      }

      try {
        const source = readFileSync(join(systemTestDir, file), 'utf-8');
        metadata.fixture_plan = sharedPlan;
        const result = await transformRuby(source, join(systemTestDir, file), 'test', config, appRoot, metadata);
        let code = result.code;

        // Skip empty test suites (no test() calls)
        if (!/\btest\s*\(/.test(code)) {
          if (existsSync(outPath)) unlinkSync(outPath);
          continue;
        }

        writeFileSync(outPath, code);
        count++;
      } catch (err) {
        console.warn(`  Warning: Failed to transpile ${file}: ${err.message}`);
      }
    }
  }

  if (count > 0) {
    console.log(`Transpiled ${count} test file${count > 1 ? 's' : ''}.`);
  }

  // Generate test/__fixtures.mjs — shared fixture creation module
  const fixturesModulePath = join(testDir, '__fixtures.mjs');
  if (fullPlan) {
    const models = fullPlan.fixtureModels || [];
    const importLine = models.length > 0
      ? `import { ${models.join(', ')} } from "juntos:models";\n\n`
      : '';
    // Extract creation body from setupCode (strip beforeEach wrapper)
    const body = fullPlan.setupCode
      .replace(/^beforeEach\(async \(\) => \{\n/, '')
      .replace(/\n\}\);$/, '');

    writeFileSync(fixturesModulePath,
`${importLine}export const _fixtures = {};

export async function loadFixtures() {
  for (const key of Object.keys(_fixtures)) delete _fixtures[key];
${body}
}
`);
  } else {
    writeFileSync(fixturesModulePath,
`export const _fixtures = {};

export async function loadFixtures() {}
`);
  }

  // Generate test/setup.mjs — always regenerate to match current juntos version
  let stimSection = '';
  const stimDir = join(appRoot, 'app/javascript/controllers');
  if (hasSystemTests && existsSync(stimDir)) {
    const stimEntries = [];
    for (const f of readdirSync(stimDir)) {
      if (f.endsWith('_controller.rb') || f.endsWith('_controller.js')) {
        const name = f.replace(/_controller\.(rb|js)$/, '').replace(/_/g, '-');
        const className = f.replace(/_controller\.(rb|js)$/, '')
          .split('_').map(w => w[0].toUpperCase() + w.slice(1)).join('') + 'Controller';
        const ext = f.endsWith('.rb') ? '.rb' : '.js';
        stimEntries.push({ name, className, file: f.replace(/\.js$/, ext) });
      }
    }
    if (stimEntries.length > 0) {
      const imports = stimEntries.map(c =>
        `import ${c.className} from '../app/javascript/controllers/${c.file}';`
      ).join('\n');
      const regs = stimEntries.map(c =>
        `registerController('${c.name}', ${c.className});`
      ).join('\n');
      stimSection = `\nimport { registerController } from 'juntos/system_test.mjs';\n${imports}\n${regs}\n`;
    }
  }

  const setupPath = join(testDir, 'setup.mjs');
  writeFileSync(setupPath, `// Test setup for Vitest
// Initializes the database once, loads fixtures, uses savepoints per test

import { beforeAll, beforeEach, afterEach, afterAll } from 'vitest';
import { installFetchInterceptor } from 'juntos/test_fetch.mjs';
import { loadFixtures, _fixtures } from './__fixtures.mjs';${stimSection}

// Suppress ActiveRecord CRUD logging during tests
const _info = console.info;
const _debug = console.debug;
console.info = () => {};
console.debug = () => {};

afterAll(() => {
  console.info = _info;
  console.debug = _debug;
});

let dbReady = false;

beforeAll(async () => {
  // Import models (registers them with Application and modelRegistry)
  await import('juntos:models');

  // Configure migrations
  const rails = await import('juntos:rails');
  const migrations = await import('juntos:migrations');
  rails.Application.configure({ migrations: migrations.migrations });

  // Import routes (registers routes with Router via RouterBase.resources())
  await import('../config/routes.rb');

  // Install fetch interceptor so Stimulus controllers can reach controller actions
  installFetchInterceptor();

  if (!dbReady) {
    const activeRecord = await import('juntos:active-record');
    await activeRecord.initDatabase({ database: ':memory:' });
    await rails.Application.runMigrations(activeRecord);
    await loadFixtures();
    globalThis.__fixtures = _fixtures;
    dbReady = true;
  }
});

beforeEach(async () => {
  const activeRecord = await import('juntos:active-record');
  activeRecord.beginSavepoint();
});

afterEach(async () => {
  const activeRecord = await import('juntos:active-record');
  activeRecord.rollbackSavepoint();
});
`);
}

// ============================================
// Argument parsing
// ============================================

function parseCommonArgs(args) {
  const options = {
    database: null,
    environment: null,
    target: null,
    port: 3000,
    verbose: false,
    help: false,
    yes: false,
    sourcemap: false,
    base: null,
    open: false,
    skipBuild: false,
    force: false,
    outDir: null,
    host: false,
    // Eject filtering options
    include: [],      // --include patterns (can be repeated)
    exclude: [],      // --exclude patterns (can be repeated)
    only: null,       // --only comma-separated list (shorthand for include-only)
    // Lint options
    disable: [],      // --disable rules (can be repeated)
    strict: false,    // --strict: enable strict lint warnings
    summary: false,   // --summary: show untyped variable summary
    suggest: false    // --suggest: auto-generate type hints
  };

  const remaining = [];
  const passthrough = []; // Args after --
  let i = 0;
  let seenDoubleDash = false;

  while (i < args.length) {
    const arg = args[i];

    // After --, collect all remaining args as passthrough
    if (arg === '--') {
      seenDoubleDash = true;
      i++;
      continue;
    }
    if (seenDoubleDash) {
      passthrough.push(arg);
      i++;
      continue;
    }

    if (arg === '-d' || arg === '--database') {
      options.database = args[++i];
    } else if (arg.startsWith('-d')) {
      options.database = arg.slice(2);
    } else if (arg.startsWith('--database=')) {
      options.database = arg.slice(11);
    } else if (arg === '-e' || arg === '--environment') {
      options.environment = args[++i];
    } else if (arg.startsWith('-e')) {
      options.environment = arg.slice(2);
    } else if (arg.startsWith('--environment=')) {
      options.environment = arg.slice(14);
    } else if (arg === '-t' || arg === '--target') {
      options.target = args[++i];
    } else if (arg.startsWith('-t')) {
      options.target = arg.slice(2);
    } else if (arg.startsWith('--target=')) {
      options.target = arg.slice(9);
    } else if (arg === '-p' || arg === '--port') {
      options.port = parseInt(args[++i], 10);
    } else if (arg.startsWith('-p')) {
      options.port = parseInt(arg.slice(2), 10);
    } else if (arg.startsWith('--port=')) {
      options.port = parseInt(arg.slice(7), 10);
    } else if (arg === '-v' || arg === '--verbose') {
      options.verbose = true;
    } else if (arg === '-y' || arg === '--yes') {
      options.yes = true;
    } else if (arg === '-o' || arg === '--open') {
      options.open = true;
    } else if (arg === '--sourcemap') {
      options.sourcemap = true;
    } else if (arg === '--skip-build') {
      options.skipBuild = true;
    } else if (arg === '-f' || arg === '--force') {
      options.force = true;
    } else if (arg === '--output' || arg === '--out') {
      options.outDir = args[++i];
    } else if (arg.startsWith('--output=')) {
      options.outDir = arg.slice(9);
    } else if (arg.startsWith('--out=')) {
      options.outDir = arg.slice(6);
    } else if (arg === '--base') {
      options.base = args[++i];
    } else if (arg.startsWith('--base=')) {
      options.base = arg.slice(7);
    } else if (arg === '-h' || arg === '--help') {
      options.help = true;
    } else if (arg === '--host' || arg === '--binding') {
      // --host (Vite style) or --binding (Rails style) - listen on all interfaces
      options.host = true;
    } else if (arg.startsWith('--binding=') || arg.startsWith('--host=')) {
      // --binding=0.0.0.0 or --host=0.0.0.0
      options.host = arg.split('=')[1] || true;
    } else if (arg === '--include') {
      options.include.push(args[++i]);
    } else if (arg.startsWith('--include=')) {
      options.include.push(arg.slice(10));
    } else if (arg === '--exclude') {
      options.exclude.push(args[++i]);
    } else if (arg.startsWith('--exclude=')) {
      options.exclude.push(arg.slice(10));
    } else if (arg === '--only') {
      options.only = args[++i];
    } else if (arg.startsWith('--only=')) {
      options.only = arg.slice(7);
    } else if (arg === '--disable') {
      options.disable.push(args[++i]);
    } else if (arg.startsWith('--disable=')) {
      options.disable.push(arg.slice(10));
    } else if (arg === '--strict') {
      options.strict = true;
    } else if (arg === '--summary') {
      options.summary = true;
    } else if (arg === '--suggest') {
      options.suggest = true;
    } else {
      remaining.push(arg);
    }
    i++;
  }

  return { options, remaining, passthrough };
}

// ============================================
// Configuration helpers
// ============================================

function loadEnvLocal() {
  const envFile = join(APP_ROOT, '.env.local');
  if (!existsSync(envFile)) return;

  const content = readFileSync(envFile, 'utf-8');
  for (const line of content.split('\n')) {
    if (line.startsWith('#') || !line.trim()) continue;
    const match = line.match(/^([^=]+)=["']?([^"'\n]*)["']?$/);
    if (match) {
      process.env[match[1]] = match[2];
    }
  }
}

function loadDatabaseConfig(options) {
  const env = options.environment || process.env.RAILS_ENV || 'development';
  process.env.RAILS_ENV = env;
  process.env.NODE_ENV = env === 'production' ? 'production' : 'development';

  // CLI options take precedence — just fill in defaults
  if (options.database) {
    if (_ADAPTER_ALIASES[options.database]) {
      options.database = _ADAPTER_ALIASES[options.database];
    }
    options.dbName = options.dbName || `${basename(APP_ROOT)}_${env}`.toLowerCase().replace(/[^a-z0-9_]/g, '_');
    return;
  }

  // Delegate to shared loader (handles yaml, naive fallback, multi-db, env overrides, aliasing)
  const dbConfig = _loadDatabaseConfig(APP_ROOT, { quiet: true });

  options.database = options.database || dbConfig.adapter || 'dexie';
  options.dbName = options.dbName || dbConfig.database;
  options.target = options.target || dbConfig.target || process.env.JUNTOS_TARGET;

  // Infer target from database if not specified
  if (!options.target && DEFAULT_TARGETS[options.database]) {
    options.target = DEFAULT_TARGETS[options.database];
  }
}

function applyEnvOptions(options) {
  if (options.database) process.env.JUNTOS_DATABASE = options.database;
  if (options.target) process.env.JUNTOS_TARGET = options.target;
  if (options.base) process.env.JUNTOS_BASE = options.base;
  if (options.environment) {
    process.env.RAILS_ENV = options.environment;
    process.env.NODE_ENV = options.environment === 'production' ? 'production' : 'development';
  }
}

function validateRailsApp() {
  if (!existsSync(join(APP_ROOT, 'app')) || !existsSync(join(APP_ROOT, 'config'))) {
    console.error('Error: Not a Rails-like application directory.');
    console.error('Expected to find app/ and config/ directories.');
    process.exit(1);
  }
}

// ============================================
// Init command - set up Juntos in a project
// ============================================

const RELEASES_URL = 'https://ruby2js.github.io/ruby2js/releases';

function runInit(options) {
  const destDir = APP_ROOT;
  const quiet = options.quiet || false;

  if (!quiet) {
    console.log(`Initializing Juntos in ${basename(destDir)}/\n`);
  }

  // Create or merge package.json
  const packagePath = join(destDir, 'package.json');
  if (existsSync(packagePath)) {
    if (!quiet) console.log('  Updating package.json...');
    const existing = JSON.parse(readFileSync(packagePath, 'utf8'));
    existing.type = existing.type || 'module';
    existing.dependencies = existing.dependencies || {};
    existing.devDependencies = existing.devDependencies || {};
    existing.scripts = existing.scripts || {};

    // Add dependencies if missing (ruby2js and vite-plugin-ruby2js are peer deps of juntos-dev)
    if (!existing.dependencies['ruby2js']) {
      existing.dependencies['ruby2js'] = `${RELEASES_URL}/ruby2js-beta.tgz`;
    }
    if (!existing.dependencies['juntos']) {
      existing.dependencies['juntos'] = `${RELEASES_URL}/juntos-beta.tgz`;
    }
    if (!existing.dependencies['vite-plugin-ruby2js']) {
      existing.dependencies['vite-plugin-ruby2js'] = `${RELEASES_URL}/vite-plugin-ruby2js-beta.tgz`;
    }
    if (!existing.devDependencies['vite']) {
      existing.devDependencies['vite'] = '^7.0.0';
    }
    if (!existing.devDependencies['vitest']) {
      existing.devDependencies['vitest'] = '^2.0.0';
    }
    if (!existing.devDependencies['jsdom']) {
      existing.devDependencies['jsdom'] = '^28.1.0';
    }

    // Add scripts if missing
    existing.scripts.dev = existing.scripts.dev || 'vite';
    existing.scripts.build = existing.scripts.build || 'vite build';
    existing.scripts.preview = existing.scripts.preview || 'vite preview';
    existing.scripts.test = existing.scripts.test || 'vitest run';

    writeFileSync(packagePath, JSON.stringify(existing, null, 2) + '\n');
  } else {
    if (!quiet) console.log('  Creating package.json...');
    const appName = basename(destDir).toLowerCase().replace(/[^a-z0-9_-]/g, '_');
    const pkg = {
      name: appName,
      type: 'module',
      scripts: {
        dev: 'vite',
        build: 'vite build',
        preview: 'vite preview',
        test: 'vitest run'
      },
      dependencies: {
        'ruby2js': `${RELEASES_URL}/ruby2js-beta.tgz`,
        'juntos': `${RELEASES_URL}/juntos-beta.tgz`,
        'vite-plugin-ruby2js': `${RELEASES_URL}/vite-plugin-ruby2js-beta.tgz`
      },
      devDependencies: {
        vite: '^7.0.0',
        vitest: '^2.0.0',
        jsdom: '^28.1.0'
      }
    };
    writeFileSync(packagePath, JSON.stringify(pkg, null, 2) + '\n');
  }

  // Read ruby2js.yml for additional dependencies
  const ruby2jsYmlPath = join(destDir, 'config/ruby2js.yml');
  if (existsSync(ruby2jsYmlPath)) {
    let ruby2jsConfig = {};
    if (yaml) {
      try {
        ruby2jsConfig = yaml.load(readFileSync(ruby2jsYmlPath, 'utf8')) || {};
      } catch (e) {
        if (!quiet) console.warn(`  Warning: Failed to parse ruby2js.yml: ${e.message}`);
      }
    }

    // Add dependencies from ruby2js.yml to package.json
    if (ruby2jsConfig.dependencies) {
      const pkg = JSON.parse(readFileSync(packagePath, 'utf8'));
      let added = false;
      for (const [name, version] of Object.entries(ruby2jsConfig.dependencies)) {
        if (!pkg.dependencies[name]) {
          pkg.dependencies[name] = version;
          added = true;
        }
      }
      if (added) {
        if (!quiet) console.log('  Adding dependencies from ruby2js.yml...');
        writeFileSync(packagePath, JSON.stringify(pkg, null, 2) + '\n');
      }
    }
  }

  // Create vite.config.js
  const viteConfigPath = join(destDir, 'vite.config.js');
  if (!existsSync(viteConfigPath)) {
    if (!quiet) console.log('  Creating vite.config.js...');
    writeFileSync(viteConfigPath, `import { defineConfig } from 'vite';
import { juntos } from 'juntos-dev/vite';

export default defineConfig({
  plugins: juntos()
});
`);
  } else {
    if (!quiet) console.log('  Skipping vite.config.js (already exists)');
  }

  // Create vitest.config.js
  const vitestConfigPath = join(destDir, 'vitest.config.js');
  if (!existsSync(vitestConfigPath)) {
    if (!quiet) console.log('  Creating vitest.config.js...');
    writeFileSync(vitestConfigPath, `import { defineConfig, mergeConfig } from 'vitest/config';
import viteConfig from './vite.config.js';

export default mergeConfig(viteConfig, defineConfig({
  test: {
    globals: true,
    environment: 'jsdom',
    include: ['test/**/*.test.mjs', 'test/**/*.test.js'],
    setupFiles: ['./test/setup.mjs'],
    pool: 'forks',
    poolOptions: { forks: { singleFork: true } }
  }
}));
`);
  } else {
    if (!quiet) console.log('  Skipping vitest.config.js (already exists)');
  }

  // Create test/setup.mjs
  const testDir = join(destDir, 'test');
  const setupPath = join(testDir, 'setup.mjs');
  if (!existsSync(setupPath)) {
    if (!quiet) console.log('  Creating test/setup.mjs...');
    if (!existsSync(testDir)) {
      mkdirSync(testDir, { recursive: true });
    }

    // Discover Stimulus controllers for system test registration
    let stimSection = '';
    const systemTestDir = join(destDir, 'test/system');
    const hasSystemTests = existsSync(systemTestDir) && readdirSync(systemTestDir).some(f => f.endsWith('.rb'));
    const stimDir = join(destDir, 'app/javascript/controllers');
    if (hasSystemTests && existsSync(stimDir)) {
      const stimEntries = [];
      for (const f of readdirSync(stimDir)) {
        if (f.endsWith('_controller.rb') || f.endsWith('_controller.js')) {
          const name = f.replace(/_controller\.(rb|js)$/, '').replace(/_/g, '-');
          const className = f.replace(/_controller\.(rb|js)$/, '')
            .split('_').map(w => w[0].toUpperCase() + w.slice(1)).join('') + 'Controller';
          const ext = f.endsWith('.rb') ? '.rb' : '.js';
          stimEntries.push({ name, className, file: f.replace(/\.js$/, ext) });
        }
      }
      if (stimEntries.length > 0) {
        const imports = stimEntries.map(c =>
          `import ${c.className} from '../app/javascript/controllers/${c.file}';`
        ).join('\n');
        const regs = stimEntries.map(c =>
          `registerController('${c.name}', ${c.className});`
        ).join('\n');
        stimSection = `\nimport { registerController } from 'juntos/system_test.mjs';\n${imports}\n${regs}\n`;
      }
    }

    writeFileSync(setupPath, `// Test setup for Vitest
// Initializes the database once, loads fixtures, uses savepoints per test

import { beforeAll, beforeEach, afterEach, afterAll } from 'vitest';
import { installFetchInterceptor } from 'juntos/test_fetch.mjs';
import { loadFixtures, _fixtures } from './__fixtures.mjs';${stimSection}

// Suppress ActiveRecord CRUD logging during tests
const _info = console.info;
const _debug = console.debug;
console.info = () => {};
console.debug = () => {};

afterAll(() => {
  console.info = _info;
  console.debug = _debug;
});

let dbReady = false;

beforeAll(async () => {
  // Import models (registers them with Application and modelRegistry)
  await import('juntos:models');

  // Configure migrations
  const rails = await import('juntos:rails');
  const migrations = await import('juntos:migrations');
  rails.Application.configure({ migrations: migrations.migrations });

  // Import routes (registers routes with Router via RouterBase.resources())
  await import('../config/routes.rb');

  // Install fetch interceptor so Stimulus controllers can reach controller actions
  installFetchInterceptor();

  if (!dbReady) {
    const activeRecord = await import('juntos:active-record');
    await activeRecord.initDatabase({ database: ':memory:' });
    await rails.Application.runMigrations(activeRecord);
    await loadFixtures();
    globalThis.__fixtures = _fixtures;
    dbReady = true;
  }
});

beforeEach(async () => {
  const activeRecord = await import('juntos:active-record');
  activeRecord.beginSavepoint();
});

afterEach(async () => {
  const activeRecord = await import('juntos:active-record');
  activeRecord.rollbackSavepoint();
});
`);
  } else {
    if (!quiet) console.log('  Skipping test/setup.mjs (already exists)');
  }

  // Create test/__fixtures.mjs stub (transpileTestFiles overwrites with real fixtures)
  const fixturesStubPath = join(testDir, '__fixtures.mjs');
  if (!existsSync(fixturesStubPath)) {
    writeFileSync(fixturesStubPath,
`export const _fixtures = {};

export async function loadFixtures() {}
`);
  }

  // Create bin/juntos binstub
  const binDir = join(destDir, 'bin');
  const binstubPath = join(binDir, 'juntos');
  if (!existsSync(binstubPath)) {
    if (!quiet) console.log('  Creating bin/juntos...');
    if (!existsSync(binDir)) {
      mkdirSync(binDir, { recursive: true });
    }
    writeFileSync(binstubPath, `#!/bin/sh
# Juntos - Rails patterns, JavaScript runtimes
# This binstub delegates to the juntos CLI from juntos-dev
exec npx juntos "$@"
`);
    chmodSync(binstubPath, 0o755);
  } else {
    if (!quiet) console.log('  Skipping bin/juntos (already exists)');
  }

  // Add .browser/ to .gitignore (generated at build time)
  const gitignorePath = join(destDir, '.gitignore');
  if (existsSync(gitignorePath)) {
    const content = readFileSync(gitignorePath, 'utf8');
    if (!content.includes('.browser/') && !content.includes('.browser\n')) {
      if (!quiet) console.log('  Adding .browser/ to .gitignore...');
      writeFileSync(gitignorePath, content.trimEnd() + '\n\n# Juntos build artifacts\n.browser/\n');
    }
  } else {
    if (!quiet) console.log('  Creating .gitignore...');
    writeFileSync(gitignorePath, `# Dependencies
node_modules/

# Build output
dist/

# Juntos build artifacts
.browser/

# Editor and OS
.DS_Store
*.swp
.idea/
.vscode/
`);
  }

  // In quiet mode or --no-install, we're done
  if (quiet || options.noInstall) {
    if (!quiet) {
      console.log('\nJuntos initialized! Run `npm install` to install dependencies.');
    }
    return;
  }

  // Run npm install
  console.log('\nInstalling dependencies...\n');
  const result = spawnSync('npm', ['install', '--prefer-online'], {
    cwd: destDir,
    stdio: 'inherit'
  });

  if (result.status !== 0) {
    console.error('\nnpm install failed. You can retry manually with: npm install');
    process.exit(1);
  }

  console.log('\nJuntos initialized!\n');
  console.log('Next steps:');
  console.log('  npx juntos dev -d dexie        # Browser with IndexedDB');
  console.log('  npx juntos up -d sqlite        # Node.js with SQLite');
  console.log('\nFor more information: https://www.ruby2js.com/docs/juntos');
}

// ============================================
// Auto-install required packages
// ============================================

const DATABASE_PACKAGES = {
  // Browser databases
  dexie: ['dexie'],
  indexeddb: ['dexie'],
  sqljs: ['sql.js'],
  'sql.js': ['sql.js'],
  pglite: ['@electric-sql/pglite'],
  // Node.js databases
  sqlite: ['better-sqlite3'],
  sqlite3: ['better-sqlite3'],
  better_sqlite3: ['better-sqlite3'],
  pg: ['pg'],
  postgres: ['pg'],
  postgresql: ['pg'],
  mysql: ['mysql2'],
  mysql2: ['mysql2'],
  // Serverless databases
  neon: ['@neondatabase/serverless'],
  turso: ['@libsql/client'],
  d1: []  // No npm package needed, uses Cloudflare bindings
};

const RUNTIME_PACKAGES = {
  browser: ['@hotwired/turbo', '@hotwired/stimulus', 'react', 'react-dom'],
  node: ['@hotwired/turbo', '@hotwired/stimulus'],
  bun: ['@hotwired/turbo', '@hotwired/stimulus'],
  deno: []
};

// Valid target environments for each database adapter
const VALID_TARGETS = {
  // Browser-only databases
  dexie: ['browser', 'capacitor'],
  sqljs: ['browser', 'capacitor', 'electron', 'tauri', 'electrobun'],
  pglite: ['browser', 'node', 'capacitor', 'electron', 'tauri', 'electrobun'],
  // Node.js databases
  sqlite: ['node', 'bun', 'electron'],
  pg: ['node', 'bun', 'deno', 'electron'],
  mysql: ['node', 'bun', 'electron'],
  // Serverless databases
  neon: ['node', 'vercel', 'vercel-edge', 'capacitor', 'electron', 'tauri', 'electrobun'],
  turso: ['node', 'vercel', 'vercel-edge', 'cloudflare', 'capacitor', 'electron', 'tauri', 'electrobun'],
  d1: ['cloudflare']
};

// Default target for each database adapter
const DEFAULT_TARGETS = {
  dexie: 'browser',
  sqljs: 'browser',
  pglite: 'browser',
  sqlite: 'node',
  pg: 'node',
  mysql: 'node',
  neon: 'vercel',
  turso: 'vercel',
  d1: 'cloudflare'
};

function validateDatabaseTarget(options) {
  const db = options.database;
  const target = options.target;

  if (!db || !target) return; // Will use defaults

  const validTargets = VALID_TARGETS[db];
  if (!validTargets) {
    console.error(`Unknown database adapter: ${db}`);
    console.error(`Valid adapters: ${Object.keys(VALID_TARGETS).join(', ')}`);
    process.exit(1);
  }

  if (!validTargets.includes(target)) {
    console.error(`Invalid combination: ${db} database with ${target} target`);
    console.error(`${db} supports: ${validTargets.join(', ')}`);
    process.exit(1);
  }
}

function ensurePackagesInstalled(options) {
  const missing = [];

  // Check database packages
  if (options.database && DATABASE_PACKAGES[options.database]) {
    for (const pkg of DATABASE_PACKAGES[options.database]) {
      if (!isPackageInstalled(pkg)) {
        missing.push(pkg);
      }
    }
  }

  // Check runtime packages for browser target
  const target = options.target || 'browser';
  if (RUNTIME_PACKAGES[target]) {
    for (const pkg of RUNTIME_PACKAGES[target]) {
      if (!isPackageInstalled(pkg)) {
        missing.push(pkg);
      }
    }
  }

  // Check if app uses broadcasting (needs ws package on node target)
  if (['node', 'bun', 'fly'].includes(target) && checkUsesBroadcasting()) {
    if (!isPackageInstalled('ws')) {
      missing.push('ws');
    }
  }

  // Install missing packages
  if (missing.length > 0) {
    console.log(`Installing required packages: ${missing.join(', ')}...`);
    try {
      execSync(`npm install ${missing.join(' ')}`, {
        cwd: APP_ROOT,
        stdio: 'inherit'
      });
    } catch (e) {
      console.error('Failed to install required packages.');
      process.exit(1);
    }
  }
}

function isPackageInstalled(packageName) {
  // Check node_modules directly
  const packagePath = join(APP_ROOT, 'node_modules', packageName);
  return existsSync(packagePath);
}

// ============================================
// Command: dev
// ============================================

function runDev(options, extraArgs = []) {
  validateRailsApp();
  loadDatabaseConfig(options);
  validateDatabaseTarget(options);
  ensurePackagesInstalled(options);
  applyEnvOptions(options);

  const args = ['vite'];
  if (options.port !== 5173) {
    args.push('--port', String(options.port));
  }
  if (options.open) {
    args.push('--open');
  }
  if (options.host) {
    // --host can be true (listen on all interfaces) or a specific address
    args.push('--host', typeof options.host === 'string' ? options.host : '');
  }
  // Pass through any additional args
  if (extraArgs.length > 0) {
    args.push(...extraArgs);
  }

  console.log('Starting Vite dev server...');
  const child = spawn('npx', args, {
    cwd: APP_ROOT,
    stdio: 'inherit',
    env: process.env
  });

  child.on('error', (err) => {
    console.error('Failed to start Vite:', err.message);
    process.exit(1);
  });
}

// ============================================
// Command: build
// ============================================

function runBuild(options, extraArgs = []) {
  validateRailsApp();
  loadDatabaseConfig(options);
  validateDatabaseTarget(options);
  ensurePackagesInstalled(options);
  applyEnvOptions(options);

  const args = ['vite', 'build'];
  if (options.sourcemap) {
    args.push('--sourcemap');
  }
  if (options.base) {
    args.push('--base', options.base);
  }
  // Pass through any additional args
  if (extraArgs.length > 0) {
    args.push(...extraArgs);
  }

  console.log('Building application...');
  const result = spawn('npx', args, {
    cwd: APP_ROOT,
    stdio: 'inherit',
    env: process.env
  });

  result.on('close', (code) => {
    if (code === 0) {
      console.log('Build complete. Output in dist/');
    } else {
      console.error('Build failed.');
      process.exit(code);
    }
  });
}

// ============================================
// Command: eject
// ============================================

async function runEject(options) {
  validateRailsApp();
  loadDatabaseConfig(options);
  applyEnvOptions(options);

  // Load eject config from ruby2js.yml
  const ejectConfig = loadEjectConfig(APP_ROOT);

  // Merge CLI options with config (CLI takes precedence)
  let includePatterns = options.include.length > 0 ? options.include : ejectConfig.include;
  let excludePatterns = options.exclude.length > 0 ? options.exclude : ejectConfig.exclude;

  // Handle --only flag (shorthand for include-only mode)
  if (options.only) {
    includePatterns = options.only.split(',').map(p => p.trim());
    excludePatterns = []; // --only implies no excludes from config
  }

  // Output directory: CLI > config > default
  const outDir = options.outDir || (ejectConfig.output ? join(APP_ROOT, ejectConfig.output) : join(APP_ROOT, 'ejected'));

  // Load full config from ruby2js.yml (same as Vite plugin uses)
  // This ensures eslevel, external, and other settings are read consistently
  // Dynamic import to avoid loading js-yaml at CLI startup
  const { loadConfig } = await import('./vite.mjs');
  const config = loadConfig(APP_ROOT, {
    database: options.database,
    target: options.target,
    base: options.base
  });

  // Helper to check if a file should be included
  const shouldInclude = (relativePath) => shouldIncludeFile(relativePath, includePatterns, excludePatterns);

  // Show filtering info if patterns are active
  if (includePatterns.length > 0 || excludePatterns.length > 0) {
    console.log('Eject filtering:');
    if (includePatterns.length > 0) {
      console.log(`  Include: ${includePatterns.join(', ')}`);
    }
    if (excludePatterns.length > 0) {
      console.log(`  Exclude: ${excludePatterns.join(', ')}`);
    }
    console.log();
  }

  console.log(`Ejecting transpiled files to ${relative(APP_ROOT, outDir) || outDir}/\n`);

  // Build models list and class name map for import resolution during eject
  config.models = findModels(APP_ROOT);
  const collisions = findLeafCollisions(config.models);
  config.modelClassMap = {};
  for (const m of config.models) {
    config.modelClassMap[modelClassName(m, collisions)] = m;
  }

  // Ensure ruby2js is ready
  await ensureRuby2jsReady();

  // Create output directory structure
  const dirs = [
    outDir,
    join(outDir, 'app/models'),
    join(outDir, 'app/views'),
    join(outDir, 'app/views/layouts'),
    join(outDir, 'app/controllers'),
    join(outDir, 'app/javascript/controllers'),
    join(outDir, 'config'),
    join(outDir, 'db/migrate')
  ];

  for (const dir of dirs) {
    if (!existsSync(dir)) {
      mkdirSync(dir, { recursive: true });
    }
  }

  let fileCount = 0;
  const errors = [];  // Track errors but continue processing

  // Pre-analyze all models: populates metadata and caches transform results.
  // buildAppManifest calls transformRuby for each model, threading a shared
  // metadata object through all transforms.
  const { metadata, modelCache } = await buildAppManifest(APP_ROOT, config, { mode: 'eject' });

  // Write cached model transforms to disk
  const modelsDir = join(APP_ROOT, 'app/models');
  if (existsSync(modelsDir)) {
    const modelFiles = findRubyModelFiles(modelsDir)
      .filter(f => shouldInclude(`app/models/${f}`));

    if (modelFiles.length > 0) {
      console.log('  Transforming models...');
      for (const file of modelFiles) {
        const relativePath = `app/models/${file}`;
        const filePath = join(modelsDir, file);
        const cached = modelCache.get(filePath);
        try {
          let code;
          if (cached) {
            // Use pre-analyzed result from buildAppManifest
            const relativeOutPath = `app/models/${file.replace('.rb', '.js')}`;
            code = fixImportsForEject(cached.code, relativeOutPath, config);
          } else {
            // Fallback: transform directly (e.g., nested model not in cache)
            let source = readFileSync(filePath, 'utf-8');
            const result = await transformRuby(source, filePath, null, config, APP_ROOT, metadata);
            const relativeOutPath = `app/models/${file.replace('.rb', '.js')}`;
            code = fixImportsForEject(result.code, relativeOutPath, config);
          }
          const outFile = join(outDir, 'app/models', file.replace('.rb', '.js'));
          // Ensure parent directory exists for nested models (e.g., account/export.js)
          const outParentDir = dirname(outFile);
          if (!existsSync(outParentDir)) {
            mkdirSync(outParentDir, { recursive: true });
          }
          writeFileSync(outFile, code);
          fileCount++;
        } catch (err) {
          errors.push({ file: relativePath, error: err.message, stack: err.stack });
          console.warn(`    Skipped ${relativePath}: ${formatError(err)}`);
        }
      }

      // Generate models index, excluding:
      // 1. Models that failed to transpile
      // 2. Models that don't have exports (e.g., nested classes like Account.Export = class)
      const failedModels = new Set(errors
        .filter(e => e.file.startsWith('app/models/'))
        .map(e => e.file.replace('app/models/', '').replace('.rb', '')));
      // Check ejected JS files for export statements.
      // If a model file defines a top-level class/function but has no export,
      // add one. This handles Struct.new + class reopening patterns where the
      // selfhost converter doesn't merge into a single `export class`.
      for (const m of config.models) {
        if (failedModels.has(m)) continue;
        const jsFile = join(outDir, 'app/models', m + '.js');
        if (existsSync(jsFile)) {
          let content = readFileSync(jsFile, 'utf-8');
          if (!content.includes('export ')) {
            const className = modelClassName(m, collisions);
            if (new RegExp(`\\b${className}\\b`).test(content)) {
              content += `\nexport { ${className} }\n`;
              writeFileSync(jsFile, content);
            } else {
              failedModels.add(m);
            }
          }
        }
      }
      const modelsIndex = generateModelsModuleForEject(APP_ROOT, { ...config, excludeModels: failedModels, outDir });
      writeFileSync(join(outDir, 'app/models/index.js'), modelsIndex);
      fileCount++;

      // Post-process: remove imports of excluded models from other model files.
      // e.g., account.js imports from './account/export.js' but that file has no exports.
      if (failedModels.size > 0) {
        for (const file of modelFiles) {
          const jsPath = join(outDir, 'app/models', file.replace('.rb', '.js'));
          if (!existsSync(jsPath)) continue;
          let content = readFileSync(jsPath, 'utf-8');
          let changed = false;
          for (const excluded of failedModels) {
            // Match import lines referencing the excluded model path
            const escapedPath = excluded.replace(/\//g, '\\/');
            const re = new RegExp(`^import\\s+\\{[^}]*\\}\\s+from\\s+['"]\\.\\.?\\/${escapedPath}\\.js['"];?\\s*\\n?`, 'gm');
            const newContent = content.replace(re, '');
            if (newContent !== content) {
              content = newContent;
              changed = true;
            }
          }
          if (changed) {
            writeFileSync(jsPath, content);
          }
        }
      }
    }

    // Transform model concerns (app/models/concerns/*.rb)
    const modelConcernsDir = join(modelsDir, 'concerns');
    if (existsSync(modelConcernsDir)) {
      const concernFiles = findRubyModelFiles(modelConcernsDir)
        .filter(f => shouldInclude(`app/models/concerns/${f}`));

      if (concernFiles.length > 0) {
        console.log('  Transforming model concerns...');
        for (const file of concernFiles) {
          const relativePath = `app/models/concerns/${file}`;
          try {
            const source = readFileSync(join(modelConcernsDir, file), 'utf-8');
            const result = await transformRuby(source, join(modelConcernsDir, file), null, config, APP_ROOT, metadata);
            const relativeOutPath = `app/models/concerns/${file.replace('.rb', '.js')}`;
            let code = fixImportsForEject(result.code, relativeOutPath, config);
            const outFile = join(outDir, 'app/models/concerns', file.replace('.rb', '.js'));
            const outParentDir = dirname(outFile);
            if (!existsSync(outParentDir)) {
              mkdirSync(outParentDir, { recursive: true });
            }
            writeFileSync(outFile, code);
            fileCount++;
          } catch (err) {
            errors.push({ file: relativePath, error: err.message, stack: err.stack });
            console.warn(`    Skipped ${relativePath}: ${formatError(err)}`);
          }
        }
      }
    }
  }

  // Transform migrations
  const migrateDir = join(APP_ROOT, 'db/migrate');
  if (existsSync(migrateDir)) {
    const migrations = findMigrations(APP_ROOT)
      .filter(m => shouldInclude(`db/migrate/${m.file}`));

    if (migrations.length > 0) {
      console.log('  Transforming migrations...');
      for (const m of migrations) {
        const relativePath = `db/migrate/${m.file}`;
        try {
          const source = readFileSync(join(migrateDir, m.file), 'utf-8');
          const result = await transformRuby(source, join(migrateDir, m.file), null, config, APP_ROOT, metadata);
          // Pass relative output path for correct import resolution
          const relativeOutPath = `db/migrate/${m.name}.js`;
          let code = fixImportsForEject(result.code, relativeOutPath, config);
          const outFile = join(outDir, 'db/migrate', m.name + '.js');
          writeFileSync(outFile, code);
          fileCount++;
        } catch (err) {
          errors.push({ file: relativePath, error: err.message, stack: err.stack });
          console.warn(`    Skipped ${relativePath}: ${formatError(err)}`);
        }
      }

      // Generate migrations index (only if we have migrations)
      const migrationsIndex = generateMigrationsModuleForEject(APP_ROOT);
      writeFileSync(join(outDir, 'db/migrate/index.js'), migrationsIndex);
      fileCount++;
    }
  }

  // Transform seeds
  const seedsFile = join(APP_ROOT, 'db/seeds.rb');
  if (existsSync(seedsFile) && shouldInclude('db/seeds.rb')) {
    console.log('  Transforming seeds...');
    try {
      const source = readFileSync(seedsFile, 'utf-8');
      const result = await transformRuby(source, seedsFile, null, config, APP_ROOT, metadata);
      // Pass relative output path for correct import resolution
      let code = fixImportsForEject(result.code, 'db/seeds.js', config);
      writeFileSync(join(outDir, 'db/seeds.js'), code);
      fileCount++;
    } catch (err) {
      errors.push({ file: 'db/seeds.rb', error: err.message, stack: err.stack });
      console.warn(`    Skipped db/seeds.rb: ${formatError(err)}`);
    }
  }

  // Transform routes - generate paths.js first, then routes.js
  // This breaks the circular dependency between routes.js and controllers
  const routesFile = join(APP_ROOT, 'config/routes.rb');
  if (existsSync(routesFile) && shouldInclude('config/routes.rb')) {
    console.log('  Transforming routes...');
    try {
      const source = readFileSync(routesFile, 'utf-8');
      const { convert } = await ensureRuby2jsReady();

      // Get routes-specific config from ruby2js.yml if available
      const routesSectionConfig = config.sections?.routes || null;

      // Generate paths.js first (path helpers only, no controller imports)
      const pathsOptions = {
        ...getBuildOptions(null, config.target, routesSectionConfig),
        file: 'config/routes.rb',
        database: config.database,
        target: config.target,
        paths_only: true,  // Generate only path helpers
        base: config.base || '/',
        metadata
      };
      const pathsResult = convert(source, pathsOptions);
      let pathsCode = pathsResult.toString();
      // For browser targets, use browser path helper
      if (config.target === 'browser') {
        pathsCode = pathsCode.replace(
          /from ['"](ruby2js-rails|juntos)\/path_helper\.mjs['"]/g,
          "from 'juntos/path_helper_browser.mjs'"
        );
      }
      writeFileSync(join(outDir, 'config/paths.js'), pathsCode);
      fileCount++;

      // Generate routes.js with paths_file option (imports from paths.js)
      const routesOptions = {
        ...getBuildOptions(null, config.target, routesSectionConfig),
        file: 'config/routes.rb',
        database: config.database,
        target: config.target,
        paths_file: './paths.js',  // Import path helpers from paths.js
        base: config.base || '/',
        metadata
      };
      const routesResult = convert(source, routesOptions);
      let routesCode = fixImportsForEject(routesResult.toString(), 'config/routes.js', config);
      writeFileSync(join(outDir, 'config/routes.js'), routesCode);
      fileCount++;
    } catch (err) {
      errors.push({ file: 'config/routes.rb', error: err.message, stack: err.stack });
      console.warn(`    Skipped config/routes.rb: ${formatError(err)}`);
    }
  }

  // Transform views
  const viewsDir = join(APP_ROOT, 'app/views');
  if (existsSync(viewsDir)) {
    console.log('  Transforming views...');
    const resources = findViewResources(APP_ROOT);

    // Recursively collect view files from a resource directory
    function collectViewFiles(dir, base) {
      const entries = readdirSync(dir, { withFileTypes: true });
      let result = [];
      for (const entry of entries) {
        if (entry.name.startsWith('.') || entry.name.startsWith('._')) continue;
        const relPath = base ? `${base}/${entry.name}` : entry.name;
        if (entry.isDirectory()) {
          result = result.concat(collectViewFiles(join(dir, entry.name), relPath));
        } else if (entry.name.endsWith('.html.erb') || entry.name.endsWith('.jsx.rb') || entry.name.endsWith('.turbo_stream.erb')) {
          result.push(relPath);
        }
      }
      return result;
    }

    for (const resource of resources) {
      const resourceDir = join(viewsDir, resource);
      const viewFiles = collectViewFiles(resourceDir, '');

      for (const relFile of viewFiles) {
        const fullPath = join(resourceDir, relFile);
        const relativePath = `app/views/${resource}/${relFile}`;
        if (!shouldInclude(relativePath)) continue;

        const outFileDir = join(outDir, 'app/views', resource, relFile, '..');
        if (!existsSync(outFileDir)) {
          mkdirSync(outFileDir, { recursive: true });
        }

        if (relFile.endsWith('.html.erb')) {
          try {
            const source = readFileSync(fullPath, 'utf-8');
            const result = await transformErb(source, fullPath, false, config);
            const relativeOutPath = `app/views/${resource}/${relFile.replace('.html.erb', '.js')}`;
            let code = fixImportsForEject(result.code, relativeOutPath, config);
            const outFile = join(outDir, 'app/views', resource, relFile.replace('.html.erb', '.js'));
            writeFileSync(outFile, code);
            fileCount++;
          } catch (err) {
            errors.push({ file: relativePath, error: err.message, stack: err.stack });
            console.warn(`    Skipped ${relativePath}: ${formatError(err)}`);
          }
        } else if (relFile.endsWith('.jsx.rb')) {
          try {
            const source = readFileSync(fullPath, 'utf-8');
            const result = await transformJsxRb(source, fullPath, config);
            const relativeOutPath = `app/views/${resource}/${relFile.replace('.jsx.rb', '.js')}`;
            let code = fixImportsForEject(result.code, relativeOutPath, config);
            const outFile = join(outDir, 'app/views', resource, relFile.replace('.jsx.rb', '.js'));
            writeFileSync(outFile, code);
            fileCount++;
          } catch (err) {
            errors.push({ file: relativePath, error: err.message, stack: err.stack });
            console.warn(`    Skipped ${relativePath}: ${formatError(err)}`);
          }
        } else if (relFile.endsWith('.turbo_stream.erb')) {
          try {
            const source = readFileSync(fullPath, 'utf-8');
            const result = await transformErb(source, fullPath, false, config);
            const relativeOutPath = `app/views/${resource}/${relFile.replace('.turbo_stream.erb', '.turbo_stream.js')}`;
            let code = fixImportsForEject(result.code, relativeOutPath, config);
            const outFile = join(outDir, 'app/views', resource, relFile.replace('.turbo_stream.erb', '.turbo_stream.js'));
            writeFileSync(outFile, code);
            fileCount++;
          } catch (err) {
            errors.push({ file: relativePath, error: err.message, stack: err.stack });
            console.warn(`    Skipped ${relativePath}: ${formatError(err)}`);
          }
        }
      }
    }

    // Generate view index modules for each resource
    for (const resource of resources) {
      const viewsIndex = generateViewsModuleForEject(APP_ROOT, resource);
      writeFileSync(join(outDir, 'app/views', resource + '.js'), viewsIndex);
      fileCount++;
    }

    // Generate turbo stream modules for each resource (if any .turbo_stream.erb files exist)
    for (const resource of resources) {
      const turboModule = generateTurboStreamModuleForEject(APP_ROOT, resource);
      if (turboModule) {
        writeFileSync(join(outDir, 'app/views', resource + '_turbo_streams.js'), turboModule);
        fileCount++;
      }
    }

    // Transform layouts
    const layoutsDir = join(viewsDir, 'layouts');
    if (existsSync(layoutsDir)) {
      const layoutFiles = readdirSync(layoutsDir)
        .filter(f => f.endsWith('.html.erb') && !f.startsWith('._'))
        .filter(f => shouldInclude(`app/views/layouts/${f}`));

      for (const file of layoutFiles) {
        const relativePath = `app/views/layouts/${file}`;
        try {
          const source = readFileSync(join(layoutsDir, file), 'utf-8');
          const result = await transformErb(source, join(layoutsDir, file), true, config);
          // Pass relative output path for correct import resolution
          const relativeOutPath = `app/views/layouts/${file.replace('.html.erb', '.js')}`;
          let code = fixImportsForEject(result.code, relativeOutPath, config);
          const outFile = join(outDir, 'app/views/layouts', file.replace('.html.erb', '.js'));
          writeFileSync(outFile, code);
          fileCount++;
        } catch (err) {
          errors.push({ file: relativePath, error: err.message, stack: err.stack });
          console.warn(`    Skipped ${relativePath}: ${formatError(err)}`);
        }
      }
    }
  }

  // Transform Stimulus controllers
  const controllersDir = join(APP_ROOT, 'app/javascript/controllers');
  if (existsSync(controllersDir)) {
    // Get all files in the controllers directory
    const allFiles = readdirSync(controllersDir)
      .filter(f => !f.startsWith('._') && !f.startsWith('.'))
      .filter(f => shouldInclude(`app/javascript/controllers/${f}`));

    if (allFiles.length > 0) {
      console.log('  Transforming Stimulus controllers...');

      for (const file of allFiles) {
        const inFile = join(controllersDir, file);
        // Skip directories
        if (!statSync(inFile).isFile()) continue;

        const relativePath = `app/javascript/controllers/${file}`;
        try {
          if (file.endsWith('.rb')) {
            // Transform Ruby files
            const source = readFileSync(inFile, 'utf-8');
            const result = await transformRuby(source, inFile, 'stimulus', config, APP_ROOT, metadata);
            // Pass relative output path for correct import resolution
            const relativeOutPath = `app/javascript/controllers/${file.replace('.rb', '.js')}`;
            let code = fixImportsForEject(result.code, relativeOutPath, config);
            const outFile = join(outDir, 'app/javascript/controllers', file.replace('.rb', '.js'));
            writeFileSync(outFile, code);
            fileCount++;
          } else if (file.endsWith('.js') || file.endsWith('.mjs')) {
            // Copy JS files as-is
            const outFile = join(outDir, 'app/javascript/controllers', file);
            copyFileSync(inFile, outFile);
            fileCount++;
          }
        } catch (err) {
          errors.push({ file: relativePath, error: err.message, stack: err.stack });
          console.warn(`    Skipped ${relativePath}: ${formatError(err)}`);
        }
      }
    }
  }

  // Transform Rails controllers
  const appControllersDir = join(APP_ROOT, 'app/controllers');
  if (existsSync(appControllersDir)) {
    // Collect controller concern names for import resolution
    const ctrlConcernsDir = join(appControllersDir, 'concerns');
    if (existsSync(ctrlConcernsDir)) {
      config.controllerConcerns = new Set(
        findRubyModelFiles(ctrlConcernsDir).map(f => f.replace(/\.rb$/, ''))
      );
    }

    const controllerFiles = findRubyModelFiles(appControllersDir)
      .filter(f => shouldInclude(`app/controllers/${f}`));

    if (controllerFiles.length > 0) {
      console.log('  Transforming Rails controllers...');
      for (const file of controllerFiles) {
        const relativePath = `app/controllers/${file}`;
        try {
          const source = readFileSync(join(appControllersDir, file), 'utf-8');
          const result = await transformRuby(source, join(appControllersDir, file), 'controllers', config, APP_ROOT, metadata);
          // Pass relative output path for correct import resolution
          const relativeOutPath = `app/controllers/${file.replace('.rb', '.js')}`;
          let code = fixImportsForEject(result.code, relativeOutPath, config);
          const outFile = join(outDir, 'app/controllers', file.replace('.rb', '.js'));
          const outParentDir = dirname(outFile);
          if (!existsSync(outParentDir)) {
            mkdirSync(outParentDir, { recursive: true });
          }
          writeFileSync(outFile, code);
          fileCount++;
        } catch (err) {
          errors.push({ file: relativePath, error: err.message, stack: err.stack });
          console.warn(`    Skipped ${relativePath}: ${formatError(err)}`);
        }
      }
    }

    // Transform controller concerns (app/controllers/concerns/*.rb)
    const concernsDir = join(appControllersDir, 'concerns');
    if (existsSync(concernsDir)) {
      const concernFiles = findRubyModelFiles(concernsDir)  // Reuse recursive finder
        .filter(f => shouldInclude(`app/controllers/concerns/${f}`));

      if (concernFiles.length > 0) {
        console.log('  Transforming controller concerns...');
        for (const file of concernFiles) {
          const relativePath = `app/controllers/concerns/${file}`;
          try {
            const source = readFileSync(join(concernsDir, file), 'utf-8');
            // Use 'model' type for concerns (they're module-like)
            const result = await transformRuby(source, join(concernsDir, file), null, config, APP_ROOT, metadata);
            const relativeOutPath = `app/controllers/concerns/${file.replace('.rb', '.js')}`;
            let code = fixImportsForEject(result.code, relativeOutPath, config);
            const outFile = join(outDir, 'app/controllers/concerns', file.replace('.rb', '.js'));
            // Ensure parent directory exists for nested concerns
            const outParentDir = dirname(outFile);
            if (!existsSync(outParentDir)) {
              mkdirSync(outParentDir, { recursive: true });
            }
            writeFileSync(outFile, code);
            fileCount++;
          } catch (err) {
            errors.push({ file: relativePath, error: err.message, stack: err.stack });
            console.warn(`    Skipped ${relativePath}: ${formatError(err)}`);
          }
        }
      }
    }
  }

  // Copy and transform test files
  const testDir = join(APP_ROOT, 'test');
  let hasFixtures = false;
  let helperExports = []; // [{ file: 'session_test_helper.mjs', exports: ['signInAs', ...] }]
  if (existsSync(testDir)) {
    // Copy .mjs and .js test files with import fixes
    const testFiles = readdirSync(testDir)
      .filter(f => (f.endsWith('.test.mjs') || f.endsWith('.test.js')) && !f.startsWith('._'))
      .filter(f => shouldInclude(`test/${f}`));

    if (testFiles.length > 0) {
      console.log('  Copying test files...');
      const outTestDir = join(outDir, 'test');
      if (!existsSync(outTestDir)) {
        mkdirSync(outTestDir, { recursive: true });
      }

      for (const file of testFiles) {
        const relativePath = `test/${file}`;
        try {
          let content = readFileSync(join(testDir, file), 'utf-8');
          content = fixTestImportsForEject(content);
          writeFileSync(join(outTestDir, file), content);
          fileCount++;
        } catch (err) {
          errors.push({ file: relativePath, error: err.message, stack: err.stack });
          console.warn(`    Skipped ${relativePath}: ${formatError(err)}`);
        }
      }
    }

    // Parse fixtures once and generate shared fixtures module
    const fixtures = parseFixtureFiles(APP_ROOT);
    const associationMap = buildAssociationMap(join(outDir, 'app/models'));
    hasFixtures = Object.keys(fixtures).length > 0;

    if (hasFixtures) {
      const currentAttributes = metadata.current_attributes || [];
      const fixturesModule = generateFixturesModule(fixtures, associationMap, currentAttributes, join(outDir, 'app/models'));
      const outTestDir2 = join(outDir, 'test');
      if (!existsSync(outTestDir2)) {
        mkdirSync(outTestDir2, { recursive: true });
      }
      writeFileSync(join(outTestDir2, 'fixtures.mjs'), fixturesModule);
      fileCount++;
      console.log('  Generated test/fixtures.mjs');

      // Set universal replacements on metadata (shared by all test files)
      metadata.fixture_plan = { replacements: buildUniversalReplacementsMap(fixtures) };
    } else {
      metadata.fixture_plan = null;
    }

    // Transpile Ruby test helper files (test/test_helpers/*.rb → .mjs)
    const testHelpersDir = join(testDir, 'test_helpers');
    if (existsSync(testHelpersDir)) {
      const helperFiles = readdirSync(testHelpersDir)
        .filter(f => f.endsWith('.rb') && !f.startsWith('._'));

      if (helperFiles.length > 0) {
        console.log('  Transpiling test helpers...');
        const outHelpersDir = join(outDir, 'test/test_helpers');
        if (!existsSync(outHelpersDir)) {
          mkdirSync(outHelpersDir, { recursive: true });
        }

        // Collect known model names for async detection
        const modelNames = Object.keys(metadata.models || {});

        for (const file of helperFiles) {
          const relativePath = `test/test_helpers/${file}`;
          const outName = file.replace(/\.rb$/, '.mjs');
          try {
            const source = readFileSync(join(testHelpersDir, file), 'utf-8');
            const result = await transformRuby(source, join(testHelpersDir, file), null, config, APP_ROOT, metadata);
            const { code, exports: exportNames } = postProcessTestHelper(result.code, modelNames);

            if (exportNames.length > 0) {
              writeFileSync(join(outHelpersDir, outName), code);
              helperExports.push({ file: outName, exports: exportNames });
              fileCount++;
            }
          } catch (err) {
            errors.push({ file: relativePath, error: err.message, stack: err.stack });
            console.warn(`    Skipped ${relativePath}: ${formatError(err)}`);
          }
        }
      }
    }

    // Transpile Ruby model test files
    const modelTestDir = join(testDir, 'models');
    if (existsSync(modelTestDir)) {
      const rubyTestFiles = findRubyTestFiles(modelTestDir);
      const filteredTestFiles = rubyTestFiles
        .filter(f => shouldInclude(`test/models/${f}`));

      if (filteredTestFiles.length > 0) {
        console.log('  Transpiling model tests...');
        const outModelTestDir = join(outDir, 'test/models');
        if (!existsSync(outModelTestDir)) {
          mkdirSync(outModelTestDir, { recursive: true });
        }

        for (const file of filteredTestFiles) {
          const relativePath = `test/models/${file}`;
          const outName = file.replace(/_test\.rb$/, '.test.mjs');
          try {
            const source = readFileSync(join(modelTestDir, file), 'utf-8');
            const result = await transformRuby(source, join(modelTestDir, file), 'test', config, APP_ROOT, metadata);
            let code = fixTestImportsForEject(result.code);

            // Ensure parent directory exists for nested test files (e.g., account/cancellable.test.mjs)
            const outPath = join(outModelTestDir, outName);
            const outParentDir = dirname(outPath);
            if (!existsSync(outParentDir)) {
              mkdirSync(outParentDir, { recursive: true });
            }
            writeFileSync(outPath, code);
            fileCount++;
          } catch (err) {
            errors.push({ file: relativePath, error: err.message, stack: err.stack });
            console.warn(`    Skipped ${relativePath}: ${formatError(err)}`);
          }
        }
      }
    }

    // Transpile Ruby controller test files
    const controllerTestDir = join(testDir, 'controllers');
    if (existsSync(controllerTestDir)) {
      const rubyControllerTestFiles = findRubyTestFiles(controllerTestDir);
      const filteredControllerTestFiles = rubyControllerTestFiles
        .filter(f => shouldInclude(`test/controllers/${f}`));

      if (filteredControllerTestFiles.length > 0) {
        console.log('  Transpiling controller tests...');
        const outControllerTestDir = join(outDir, 'test/controllers');
        if (!existsSync(outControllerTestDir)) {
          mkdirSync(outControllerTestDir, { recursive: true });
        }

        for (const file of filteredControllerTestFiles) {
          const relativePath = `test/controllers/${file}`;
          const outName = file.replace(/_test\.rb$/, '.test.mjs');
          try {
            const source = readFileSync(join(controllerTestDir, file), 'utf-8');
            const result = await transformRuby(source, join(controllerTestDir, file), 'test', config, APP_ROOT, metadata);
            let code = fixTestImportsForEject(result.code);

            // Ensure parent directory exists for nested test files (e.g., cards/comments_controller.test.mjs)
            const outPath = join(outControllerTestDir, outName);
            const outParentDir = dirname(outPath);
            if (!existsSync(outParentDir)) {
              mkdirSync(outParentDir, { recursive: true });
            }
            writeFileSync(outPath, code);
            fileCount++;
          } catch (err) {
            errors.push({ file: relativePath, error: err.message, stack: err.stack });
            console.warn(`    Skipped ${relativePath}: ${formatError(err)}`);
          }
        }
      }
    }
  }

  // Generate project files
  console.log('  Generating project files...');

  // Generate package.json with database config
  const appName = basename(APP_ROOT) + '-ejected';
  writeFileSync(join(outDir, 'package.json'), generatePackageJsonForEject(appName, config));
  fileCount++;

  // Generate vite.config.js
  writeFileSync(join(outDir, 'vite.config.js'), generateViteConfigForEject(config));
  fileCount++;

  // Generate vitest.config.js
  writeFileSync(join(outDir, 'vitest.config.js'), generateVitestConfigForEject(config));
  fileCount++;

  // Discover Stimulus controllers for system test registration (only needed for system tests)
  const stimulusControllers = [];
  const ejectSystemTestDir = join(APP_ROOT, 'test/system');
  const ejectHasSystemTests = existsSync(ejectSystemTestDir) && readdirSync(ejectSystemTestDir).some(f => f.endsWith('.rb'));
  const stimControllersDir = join(APP_ROOT, 'app/javascript/controllers');
  if (ejectHasSystemTests && existsSync(stimControllersDir)) {
    for (const file of readdirSync(stimControllersDir)) {
      if (file.endsWith('_controller.rb') || file.endsWith('_controller.js')) {
        const ext = file.endsWith('.rb') ? '.rb' : '.js';
        const jsFile = file.replace(/\.rb$/, '.js');
        const name = file.replace(/_controller\.(rb|js)$/, '').replace(/_/g, '-');
        const className = file.replace(/_controller\.(rb|js)$/, '')
          .split('_').map(w => w[0].toUpperCase() + w.slice(1)).join('') + 'Controller';
        stimulusControllers.push({ name, className, file: jsFile });
      }
    }
  }

  // Generate test/setup.mjs and test/globals.mjs
  const outTestDir = join(outDir, 'test');
  if (!existsSync(outTestDir)) {
    mkdirSync(outTestDir, { recursive: true });
  }
  writeFileSync(join(outTestDir, 'setup.mjs'), generateTestSetupForEject({ ...config, hasFixtures, helpers: helperExports, stimulusControllers }));
  fileCount++;
  writeFileSync(join(outTestDir, 'globals.mjs'), generateTestGlobalsForEject());
  fileCount++;

  // Generate lightweight Node-native test runner (bypasses Vite, avoids OOM)
  writeFileSync(join(outTestDir, 'runner.mjs'), generateTestRunnerForEject());
  writeFileSync(join(outTestDir, 'register-loader.mjs'), generateTestLoaderRegistration());
  writeFileSync(join(outTestDir, 'vitest-loader.mjs'), generateTestLoaderHooks());
  writeFileSync(join(outTestDir, 'vitest-shim.mjs'), generateTestVitestShim());
  fileCount += 4;

  // Generate entry point(s) based on target
  const browserTargets = ['browser', 'pwa', 'capacitor', 'electron', 'tauri'];
  const isBrowserTarget = browserTargets.includes(config.target);

  if (isBrowserTarget) {
    // Browser targets: generate index.html and browser main.js
    writeFileSync(join(outDir, 'index.html'), generateBrowserIndexHtml(appName, './main.js'));
    fileCount++;
    writeFileSync(join(outDir, 'main.js'), generateBrowserMainJs('./config/routes.js', './app/javascript/controllers/index.js'));
    fileCount++;
  } else {
    // Server targets: generate Node.js server entry
    writeFileSync(join(outDir, 'main.js'), generateMainJsForEject(config));
    fileCount++;
  }

  console.log(`\nEjected ${fileCount} files to ${relative(APP_ROOT, outDir) || outDir}/`);

  // In DEBUG mode, run node --check on all generated JS files
  if (DEBUG) {
    console.log('\nChecking JavaScript syntax...');
    const syntaxErrors = [];

    // Recursively find all .js and .mjs files in outDir
    const findJsFiles = (dir) => {
      const files = [];
      for (const entry of readdirSync(dir, { withFileTypes: true })) {
        const fullPath = join(dir, entry.name);
        if (entry.isDirectory()) {
          files.push(...findJsFiles(fullPath));
        } else if (entry.name.endsWith('.js') || entry.name.endsWith('.mjs')) {
          files.push(fullPath);
        }
      }
      return files;
    };

    const jsFiles = findJsFiles(outDir);
    for (const file of jsFiles) {
      try {
        execSync(`node --check "${file}"`, { stdio: 'pipe' });
      } catch (err) {
        const relPath = relative(outDir, file);
        const stderr = err.stderr ? err.stderr.toString() : err.message;
        syntaxErrors.push({ file: relPath, error: stderr.trim() });
      }
    }

    if (syntaxErrors.length > 0) {
      console.log(`\n${syntaxErrors.length} file(s) have syntax errors:`);
      for (const e of syntaxErrors) {
        console.log(`\n  ${e.file}:`);
        // Indent error message
        console.log(e.error.split('\n').map(line => '    ' + line).join('\n'));
      }
    } else {
      console.log(`  All ${jsFiles.length} JavaScript files passed syntax check.`);
    }
  }

  console.log('\nThe ejected project depends on juntos for runtime support.');
  console.log('To use:');
  console.log('  cd ' + (relative(APP_ROOT, outDir) || outDir));
  console.log('  npm install');
  if (isBrowserTarget) {
    console.log('  npm run dev     # start dev server');
    console.log('  npm run build   # build for production');
  } else {
    console.log('  npm test        # run tests');
    console.log('  npm start       # start server');
  }

  // Report any errors that occurred
  if (errors.length > 0) {
    console.log(`\n${errors.length} file(s) failed to transform:`);
    for (const e of errors) {
      if (DEBUG && e.stack) {
        console.log(`\n  ${e.file}:`);
        console.log(e.stack.split('\n').map(line => '    ' + line).join('\n'));
      } else {
        console.log(`  ${e.file}: ${e.error}`);
      }
    }
    if (!DEBUG && errors.some(e => e.stack)) {
      console.log('\nTip: Set DEBUG=1 for full stack traces');
    }
  }
}

// ============================================
// Command: up
// ============================================

function runUp(options) {
  validateRailsApp();
  loadDatabaseConfig(options);
  validateDatabaseTarget(options);
  ensurePackagesInstalled(options);
  applyEnvOptions(options);

  const isServerTarget = ['node', 'bun', 'deno'].includes(options.target);

  console.log('Building application...');
  try {
    const buildCmd = options.base
      ? `npx vite build --base ${options.base}`
      : 'npx vite build';
    execSync(buildCmd, { cwd: APP_ROOT, stdio: 'inherit', env: process.env });
  } catch (e) {
    console.error('Build failed.');
    process.exit(1);
  }

  if (isServerTarget) {
    console.log(`Starting ${options.target} server...`);
    const runtime = options.target === 'bun' ? 'bun' : options.target === 'deno' ? 'deno' : 'node';
    const entryPoint = join(APP_ROOT, 'dist', 'index.js');

    if (!existsSync(entryPoint)) {
      console.error(`Error: ${entryPoint} not found. Build may have failed.`);
      process.exit(1);
    }

    const env = { ...process.env, PORT: String(options.port) };
    if (options.host) {
      env.HOST = typeof options.host === 'string' ? options.host : '0.0.0.0';
    }

    spawn(runtime, [entryPoint], {
      cwd: APP_ROOT,  // Run from app root to access node_modules
      stdio: 'inherit',
      env
    });
  } else {
    console.log('Starting preview server...');
    const previewArgs = ['vite', 'preview', '--port', String(options.port)];
    if (options.host) {
      previewArgs.push('--host', typeof options.host === 'string' ? options.host : '');
    }
    spawn('npx', previewArgs, {
      cwd: APP_ROOT,
      stdio: 'inherit',
      env: process.env
    });
  }
}

// ============================================
// Command: server
// ============================================

function runServer(options) {
  validateRailsApp();
  loadDatabaseConfig(options);
  validateDatabaseTarget(options);
  ensurePackagesInstalled(options);
  applyEnvOptions(options);

  // Check that app has been built
  if (!existsSync(join(APP_ROOT, 'dist'))) {
    console.error('Error: dist/ not found. Run "juntos build" first.');
    process.exit(1);
  }

  process.env.PORT = String(options.port);
  if (options.environment) {
    process.env.NODE_ENV = options.environment === 'production' ? 'production' : 'development';
  }

  const isServerTarget = ['node', 'bun', 'deno'].includes(options.target);

  if (isServerTarget) {
    // Run the built server directly (like 'up' command)
    const runtime = options.target === 'bun' ? 'bun' : options.target === 'deno' ? 'deno' : 'node';
    const entryPoint = join(APP_ROOT, 'dist', 'index.js');

    if (!existsSync(entryPoint)) {
      console.error(`Error: ${entryPoint} not found. Run "juntos build -t ${options.target}" first.`);
      process.exit(1);
    }

    const env = { ...process.env, PORT: String(options.port) };
    if (options.host) {
      env.HOST = typeof options.host === 'string' ? options.host : '0.0.0.0';
    }

    console.log(`Starting ${runtime} server on port ${options.port}...`);
    spawn(runtime, [entryPoint], {
      cwd: APP_ROOT,
      stdio: 'inherit',
      env
    });
  } else {
    // Browser target - serve static files with vite preview
    console.log(`Starting static server on port ${options.port}...`);
    const previewArgs = ['vite', 'preview', '--port', String(options.port)];
    if (options.host) {
      previewArgs.push('--host', typeof options.host === 'string' ? options.host : '');
    }
    spawn('npx', previewArgs, {
      cwd: APP_ROOT,
      stdio: 'inherit',
      env: process.env
    });
  }
}

// ============================================
// Command: db
// ============================================

const BROWSER_DATABASES = ['dexie'];

function runDb(args, options) {
  const subcommand = args[0];

  if (!subcommand || options.help) {
    showDbHelp();
    process.exit(subcommand ? 0 : 1);
  }

  const validCommands = ['migrate', 'seed', 'prepare', 'reset', 'create', 'drop'];
  if (!validCommands.includes(subcommand)) {
    console.error(`Unknown db command: ${subcommand}`);
    console.error("Run 'juntos db --help' for usage.");
    process.exit(1);
  }

  validateRailsApp();
  loadEnvLocal();
  loadDatabaseConfig(options);
  applyEnvOptions(options);

  switch (subcommand) {
    case 'migrate':
      runDbMigrate(options);
      break;
    case 'seed':
      runDbSeed(options);
      break;
    case 'prepare':
      runDbPrepare(options);
      break;
    case 'reset':
      runDbReset(options);
      break;
    case 'create':
      runDbCreate(options);
      break;
    case 'drop':
      runDbDrop(options);
      break;
  }
}

function validateNotBrowser(options, command) {
  if (BROWSER_DATABASES.includes(options.database)) {
    console.error(`Error: Browser databases (${options.database}) auto-migrate at runtime.`);
    console.error('No CLI command needed - migrations run when the app loads in the browser.');
    process.exit(1);
  }
}

function runDbMigrate(options) {
  validateNotBrowser(options, 'migrate');

  if (options.database === 'd1') {
    runD1Migrate(options);
  } else {
    runNodeMigrate(options);
  }
}

function runDbSeed(options) {
  validateNotBrowser(options, 'seed');

  if (options.database === 'd1') {
    runD1Seed(options);
  } else {
    runNodeSeed(options);
  }
}

function runDbPrepare(options) {
  validateNotBrowser(options, 'prepare');

  if (options.database === 'd1') {
    // Check if database exists, create if not
    const env = options.environment || 'development';
    const dbId = getD1DatabaseId(env);
    if (!dbId) {
      console.log(`No ${d1EnvVar(env)} found. Creating database...`);
      runDbCreate(options);
    }
    runD1Prepare(options);
  } else {
    runNodePrepare(options);
  }
}

function runDbReset(options) {
  validateNotBrowser(options, 'reset');

  const env = options.environment || 'development';
  console.log(`Resetting ${options.database} database for ${env}...`);

  console.log('\nStep 1/4: Dropping database...');
  runDbDrop(options);

  if (['d1', 'turso', 'mpg'].includes(options.database)) {
    console.log('\nStep 2/4: Creating database...');
    runDbCreate(options);
  } else {
    console.log(`\nStep 2/4: Skipping create (${options.database} creates automatically)`);
  }

  console.log('\nStep 3/4: Running migrations...');
  runDbMigrate(options);

  console.log('\nStep 4/4: Running seeds...');
  runDbSeed(options);

  console.log('\nDatabase reset complete.');
}

function runDbCreate(options) {
  switch (options.database) {
    case 'd1':
      runD1Create(options);
      break;
    case 'sqlite':
    case 'better_sqlite3':
      console.log('SQLite databases are created automatically by db:migrate.');
      break;
    case 'dexie':
      console.log('Dexie (IndexedDB) databases are created automatically in the browser.');
      break;
    default:
      console.log(`Database creation for '${options.database}' is not supported via CLI.`);
      console.log('Please create your database using your database provider\'s tools.');
  }
}

function runDbDrop(options) {
  switch (options.database) {
    case 'd1':
      runD1Drop(options);
      break;
    case 'sqlite':
    case 'better_sqlite3':
      runSqliteDrop(options);
      break;
    case 'dexie':
      console.log('Dexie (IndexedDB) databases are managed by the browser.');
      console.log('Use browser DevTools > Application > IndexedDB to delete.');
      break;
    default:
      console.log(`Database deletion for '${options.database}' is not supported via CLI.`);
  }
}

// D1 helpers
function d1EnvVar(env = 'development') {
  return env === 'development' ? 'D1_DATABASE_ID' : `D1_DATABASE_ID_${env.toUpperCase()}`;
}

function getD1DatabaseId(env = 'development') {
  const varName = d1EnvVar(env);
  return process.env[varName] || process.env.D1_DATABASE_ID;
}

function saveD1DatabaseId(databaseId, env = 'development') {
  const envFile = join(APP_ROOT, '.env.local');
  const varName = d1EnvVar(env);

  let lines = [];
  if (existsSync(envFile)) {
    lines = readFileSync(envFile, 'utf-8').split('\n');
    lines = lines.filter(line => !line.startsWith(`${varName}=`));
  }
  lines.push(`${varName}=${databaseId}`);
  writeFileSync(envFile, lines.join('\n') + '\n');
}

function runD1Create(options) {
  const dbName = options.dbName;
  const env = options.environment || 'development';

  console.log(`Creating D1 database '${dbName}' for ${env}...`);

  try {
    const output = execSync(`npx wrangler d1 create ${dbName} 2>&1`, { encoding: 'utf-8' });
    if (options.verbose) console.log(output);

    const match = output.match(/"?database_id"?\s*[=:]\s*"?([a-f0-9-]+)"?/i);
    if (match) {
      const databaseId = match[1];
      saveD1DatabaseId(databaseId, env);
      console.log(`Created D1 database: ${dbName}`);
      console.log(`Database ID: ${databaseId}`);
      console.log(`Saved to .env.local (${d1EnvVar(env)})`);
    } else if (output.includes('already exists')) {
      console.log(`Database '${dbName}' already exists.`);
    } else {
      console.error('Error: Failed to create database.');
      console.error(output);
      process.exit(1);
    }
  } catch (e) {
    console.error('Error: Failed to create database.');
    console.error(e.message);
    process.exit(1);
  }
}

function runD1Drop(options) {
  const dbName = options.dbName;
  const env = options.environment || 'development';

  console.log(`Deleting D1 database '${dbName}'...`);

  try {
    execSync(`npx wrangler d1 delete ${dbName}`, { stdio: 'inherit' });

    // Remove from .env.local
    const envFile = join(APP_ROOT, '.env.local');
    if (existsSync(envFile)) {
      const varName = d1EnvVar(env);
      let lines = readFileSync(envFile, 'utf-8').split('\n');
      lines = lines.filter(line => !line.startsWith(`${varName}=`));
      writeFileSync(envFile, lines.join('\n'));
    }

    console.log('Database deleted and removed from .env.local');
  } catch (e) {
    console.error('Error: Failed to delete database.');
    process.exit(1);
  }
}

function runD1Migrate(options) {
  const dbName = options.dbName;
  console.log(`Running D1 migrations on '${dbName}'...`);

  const migrationsFile = join(APP_ROOT, 'dist', 'db', 'migrations.sql');
  if (!existsSync(migrationsFile)) {
    console.log('Building app to generate migrations...');
    execSync('npx vite build', { cwd: APP_ROOT, stdio: 'inherit', env: process.env });
  }

  const cmd = ['npx', 'wrangler', 'd1', 'execute', dbName, '--remote', '--file', 'dist/db/migrations.sql'];
  if (options.yes) cmd.push('--yes');

  try {
    execSync(cmd.join(' '), { cwd: APP_ROOT, stdio: 'inherit' });
    console.log('Migrations completed.');
  } catch (e) {
    console.error('Error: Migration failed.');
    process.exit(1);
  }
}

function runD1Seed(options) {
  const dbName = options.dbName;
  const seedsFile = join(APP_ROOT, 'dist', 'db', 'seeds.sql');

  if (!existsSync(seedsFile)) {
    console.log('No seeds.sql found - nothing to seed.');
    return;
  }

  console.log(`Running D1 seeds on '${dbName}'...`);

  const cmd = ['npx', 'wrangler', 'd1', 'execute', dbName, '--remote', '--file', 'dist/db/seeds.sql'];
  if (options.yes) cmd.push('--yes');

  try {
    execSync(cmd.join(' '), { cwd: APP_ROOT, stdio: 'inherit' });
    console.log('Seeds completed.');
  } catch (e) {
    console.error('Error: Seeding failed.');
    process.exit(1);
  }
}

function runD1Prepare(options) {
  const dbName = options.dbName;

  // Build first
  console.log('Building app...');
  execSync('npx vite build', { cwd: APP_ROOT, stdio: 'inherit', env: process.env });

  // Check if fresh
  let isFresh = true;
  try {
    const output = execSync(
      `npx wrangler d1 execute ${dbName} --remote --command="SELECT name FROM sqlite_master WHERE type='table' AND name='schema_migrations';"`,
      { encoding: 'utf-8', cwd: APP_ROOT }
    );
    isFresh = !output.includes('schema_migrations');
  } catch (e) {
    // Assume fresh if we can't check
  }

  // Migrate
  console.log('Running D1 migrations...');
  try {
    execSync(`npx wrangler d1 execute ${dbName} --remote --file dist/db/migrations.sql --yes`, {
      cwd: APP_ROOT,
      stdio: 'inherit'
    });
  } catch (e) {
    console.error('Error: Migration failed.');
    process.exit(1);
  }

  // Seed if fresh
  const seedsFile = join(APP_ROOT, 'dist', 'db', 'seeds.sql');
  if (isFresh && existsSync(seedsFile)) {
    console.log('Running D1 seeds (fresh database)...');
    try {
      execSync(`npx wrangler d1 execute ${dbName} --remote --file dist/db/seeds.sql --yes`, {
        cwd: APP_ROOT,
        stdio: 'inherit'
      });
    } catch (e) {
      console.error('Error: Seeding failed.');
      process.exit(1);
    }
  } else if (!isFresh) {
    console.log('Skipping seeds (existing database)');
  }

  console.log('Database prepared.');
}

// Node.js database helpers
function runNodeMigrate(options) {
  console.log('Running migrations...');
  try {
    // Run migrate.mjs from this package
    execSync(`node "${MIGRATE_SCRIPT}" --migrate-only`, {
      cwd: APP_ROOT,
      stdio: 'inherit',
      env: { ...process.env, JUNTOS_DIST_DIR: join(APP_ROOT, 'dist') }
    });
    console.log('Migrations completed.');
  } catch (e) {
    console.error('Error: Migration failed.');
    process.exit(1);
  }
}

function runNodeSeed(options) {
  console.log('Running seeds...');
  try {
    execSync(`node "${MIGRATE_SCRIPT}" --seed-only`, {
      cwd: APP_ROOT,
      stdio: 'inherit',
      env: { ...process.env, JUNTOS_DIST_DIR: join(APP_ROOT, 'dist') }
    });
    console.log('Seeds completed.');
  } catch (e) {
    console.error('Error: Seeding failed.');
    process.exit(1);
  }
}

function runNodePrepare(options) {
  console.log('Running migrations and seeds...');
  try {
    execSync(`node "${MIGRATE_SCRIPT}"`, {
      cwd: APP_ROOT,
      stdio: 'inherit',
      env: { ...process.env, JUNTOS_DIST_DIR: join(APP_ROOT, 'dist') }
    });
    console.log('Database prepared.');
  } catch (e) {
    console.error('Error: Database preparation failed.');
    process.exit(1);
  }
}

function runSqliteDrop(options) {
  const patterns = [
    'storage/development.sqlite3',
    'storage/production.sqlite3',
    'db/development.sqlite3',
    'db/production.sqlite3'
  ];

  for (const pattern of patterns) {
    const fullPath = join(APP_ROOT, pattern);
    if (existsSync(fullPath)) {
      console.log(`Deleting SQLite database: ${pattern}`);
      unlinkSync(fullPath);
      console.log('Database deleted.');
      return;
    }
  }

  console.log('No SQLite database file found.');
}

function showDbHelp() {
  console.log(`
Juntos Database Commands

Usage: juntos db <command> [options]
       juntos db:command [options]

Commands:
  migrate   Run database migrations
  seed      Run database seeds
  prepare   Migrate, and seed if fresh database
  reset     Drop, create, migrate, and seed
  create    Create database (D1, Turso)
  drop      Delete database (D1, SQLite)

Options:
  -d, --database ADAPTER   Database adapter (d1, sqlite, dexie, etc.)
  -e, --environment ENV    Rails environment (development, production, etc.)
  -y, --yes                Skip confirmation prompts
  -v, --verbose            Show detailed output
  -h, --help               Show this help message

Examples:
  juntos db:migrate                    # Run migrations (uses database.yml)
  juntos db:seed                       # Run seeds
  juntos db:prepare                    # Migrate + seed if fresh
  juntos db:prepare -e production      # Prepare production database
  juntos db:create -d d1               # Create D1 database
  juntos db:drop                       # Delete database

Note: Browser databases (dexie) auto-migrate at runtime.
`);
}

// ============================================
// Command: lint
// ============================================

/**
 * Recursively find all lintable files (*.rb, *.html.erb, *.turbo_stream.erb) in a directory.
 */
function findAllLintableFiles(dir) {
  const files = [];
  if (!existsSync(dir)) return files;
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (entry.name.startsWith('.') || entry.name.startsWith('._')) continue;
    const full = join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...findAllLintableFiles(full));
    } else if (entry.name.endsWith('.rb')) {
      files.push(full);
    } else if (entry.name.endsWith('.html.erb') || entry.name.endsWith('.turbo_stream.erb')) {
      files.push(full);
    }
  }
  return files;
}

/**
 * Determine the transform section for a file based on its path.
 */
function inferSection(filePath, appRoot) {
  const rel = relative(appRoot, filePath);
  if (rel.startsWith('app/models/')) return 'models';
  if (rel.startsWith('app/controllers/') || rel.startsWith('app/javascript/controllers/')) return 'controllers';
  if (rel.startsWith('app/views/') && filePath.endsWith('.erb')) return 'erb';
  if (rel.startsWith('app/views/')) return null; // non-ERB views (e.g. .jsx.rb)
  if (rel.startsWith('config/routes')) return 'routes';
  if (rel.startsWith('test/') || rel.startsWith('spec/')) return 'models'; // test files use model section defaults
  return null;
}

/**
 * Build an array of byte offsets for each line start in a string.
 */
function buildLineOffsets(src) {
  const offsets = [0];
  for (let i = 0; i < src.length; i++) {
    if (src[i] === '\n') offsets.push(i + 1);
  }
  return offsets;
}

/**
 * Convert a byte offset to a 1-based line and 0-based column.
 */
function byteToLineCol(lineOffsets, byte) {
  let line = 1;
  for (let i = 1; i < lineOffsets.length; i++) {
    if (lineOffsets[i] > byte) break;
    line = i + 1;
  }
  return [line, byte - lineOffsets[line - 1]];
}

/**
 * Remap diagnostic line/column from generated Ruby coordinates back to ERB coordinates
 * using the ErbCompiler's position_map.
 */
function remapDiagnosticLines(diagnostics, rubySrc, erbSrc, positionMap) {
  const rubyLines = buildLineOffsets(rubySrc);
  const erbLines = buildLineOffsets(erbSrc);

  for (const d of diagnostics) {
    if (!d.line) continue;
    // Convert ruby line/col to byte offset
    const lineIdx = d.line - 1;
    if (lineIdx < 0 || lineIdx >= rubyLines.length) continue;
    const rubyByte = rubyLines[lineIdx] + (d.column || 0);
    // Look up in position_map: [ruby_start, ruby_end, erb_start, erb_end]
    for (const [rStart, rEnd, eStart, eEnd] of positionMap) {
      if (rubyByte >= rStart && rubyByte < rEnd) {
        const erbByte = eStart + (rubyByte - rStart);
        const [line, col] = byteToLineCol(erbLines, erbByte);
        d.line = line;
        d.column = col;
        break;
      }
    }
  }
}

async function runLint(files, options) {
  // Load config
  const { loadConfig } = await import('./vite.mjs');
  const config = loadConfig(APP_ROOT, {
    database: options.database,
    target: options.target
  });

  // Load lint config from ruby2js.yml
  let lintConfig = {};
  const ruby2jsPath = join(APP_ROOT, 'config/ruby2js.yml');
  if (existsSync(ruby2jsPath) && yaml) {
    try {
      const parsed = yaml.load(readFileSync(ruby2jsPath, 'utf8'));
      lintConfig = parsed?.lint || {};
    } catch { /* ignore parse errors */ }
  }

  // Merge disabled rules: CLI flags + config file
  const disabledRules = new Set([
    ...options.disable,
    ...(lintConfig.disable || [])
  ]);

  // Include/exclude patterns: CLI flags + config file
  const includePatterns = [
    ...options.include,
    ...(lintConfig.include || [])
  ];
  const excludePatterns = [
    ...options.exclude,
    ...(lintConfig.exclude || [])
  ];

  // Discover files
  let filePaths;
  if (files.length > 0) {
    // Explicit files from command args
    filePaths = files.map(f => {
      const full = f.startsWith('/') ? f : join(APP_ROOT, f);
      return full;
    }).filter(f => existsSync(f));
  } else {
    // Scan default directories
    filePaths = [
      ...findAllLintableFiles(join(APP_ROOT, 'app/models')),
      ...findAllLintableFiles(join(APP_ROOT, 'app/controllers')),
      ...findAllLintableFiles(join(APP_ROOT, 'app/javascript/controllers')),
      ...findAllLintableFiles(join(APP_ROOT, 'app/views'))
    ];

    // Add individual files if they exist
    for (const f of ['config/routes.rb', 'db/seeds.rb']) {
      const full = join(APP_ROOT, f);
      if (existsSync(full)) filePaths.push(full);
    }
  }

  // Apply include/exclude filtering
  if (includePatterns.length > 0 || excludePatterns.length > 0) {
    filePaths = filePaths.filter(f => {
      const rel = relative(APP_ROOT, f);
      return shouldIncludeFile(rel, includePatterns, excludePatterns);
    });
  }

  if (filePaths.length === 0) {
    console.log('No files found to lint.');
    return;
  }

  // Lint each file
  let totalErrors = 0;
  let totalWarnings = 0;
  let filesWithIssues = 0;
  const allDiagnostics = [];

  for (const filePath of filePaths) {
    let source = readFileSync(filePath, 'utf8');
    const section = inferSection(filePath, APP_ROOT);
    const relPath = relative(APP_ROOT, filePath);

    // Compile ERB to Ruby before linting
    let erbPositionMap = null;
    let erbSource = null;
    if (filePath.endsWith('.erb')) {
      erbSource = source;
      const compiler = new ErbCompiler(source);
      source = compiler.src;
      erbPositionMap = compiler.position_map;
    }

    let diagnostics;
    try {
      diagnostics = await lintRuby(source, filePath, section, config, APP_ROOT, {
        strict: options.strict,
        type_hints: lintConfig.type_hints || {}
      });
    } catch (err) {
      diagnostics = [{
        severity: 'error', rule: 'lint_error',
        message: err.message, file: relPath, line: null, column: null
      }];
    }

    // Remap line numbers from generated Ruby back to ERB source
    if (erbPositionMap && erbPositionMap.length > 0) {
      remapDiagnosticLines(diagnostics, source, erbSource, erbPositionMap);
    }

    // Filter out disabled rules
    diagnostics = diagnostics.filter(d => !disabledRules.has(d.rule));

    if (diagnostics.length === 0) continue;
    filesWithIssues++;
    allDiagnostics.push(...diagnostics);

    for (const d of diagnostics) {
      const sev = d.severity === 'error' ? '\x1b[31merror\x1b[0m' : '\x1b[33mwarning\x1b[0m';
      const loc = d.line ? `${d.file}:${d.line}${d.column != null ? ':' + d.column : ''}` : d.file;
      console.log(`  ${loc} ${sev}: ${d.message} [${d.rule}]`);

      // Show pragma hint for ambiguous methods
      if (d.rule === 'ambiguous_method' && d.valid_types?.length > 0) {
        const hints = d.valid_types.map(t => `# Pragma: ${t}`).join(' or ');
        console.log(`    Consider: ${hints}`);
      }

      if (d.severity === 'error') totalErrors++;
      else totalWarnings++;
    }
  }

  console.log('');
  console.log(`Linted ${filePaths.length} files: ${totalErrors} errors, ${totalWarnings} warnings`);

  // Summary: group ambiguous_method warnings by receiver name
  if (options.summary && allDiagnostics.length > 0) {
    const byName = new Map();
    for (const d of allDiagnostics) {
      if (d.rule !== 'ambiguous_method' || !d.receiver_name) continue;
      const name = d.receiver_name;
      if (!byName.has(name)) byName.set(name, { count: 0, methods: new Set() });
      const entry = byName.get(name);
      entry.count++;
      entry.methods.add(d.method);
    }

    if (byName.size > 0) {
      // Sort by count descending
      const sorted = [...byName.entries()].sort((a, b) => b[1].count - a[1].count);
      const unnamed = allDiagnostics.filter(d => d.rule === 'ambiguous_method' && !d.receiver_name).length;

      console.log('');
      console.log('Untyped variables (add type hints to resolve):');
      console.log('  Count  Name                Methods');
      console.log('  -----  ------------------  -------');
      for (const [name, { count, methods }] of sorted) {
        const methodList = [...methods].sort().join(', ');
        console.log(`  ${String(count).padStart(5)}  ${name.padEnd(18)}  ${methodList}`);
      }
      if (unnamed > 0) {
        console.log(`  ${String(unnamed).padStart(5)}  (expression)        (non-variable receivers)`);
      }
      console.log('');
      console.log(`  ${sorted.length} unique variable names, ${allDiagnostics.filter(d => d.rule === 'ambiguous_method').length} total ambiguous warnings`);
    }
  }

  // --suggest: auto-generate type hints from diagnostic patterns
  if (options.suggest && allDiagnostics.length > 0) {
    const suggestions = suggestTypeHints(allDiagnostics);

    if (suggestions.high.length > 0 || suggestions.medium.length > 0) {
      const totalSuggestions = suggestions.high.length + suggestions.medium.length;
      const coveredWarnings = suggestions.high.reduce((n, s) => n + s.count, 0)
        + suggestions.medium.reduce((n, s) => n + s.count, 0);

      console.log('');
      console.log(`Type hint suggestions (${totalSuggestions} variables, covering ${coveredWarnings} of ${totalWarnings} warnings):`);

      if (suggestions.high.length > 0) {
        console.log('');
        console.log('  High confidence:');
        for (const s of suggestions.high) {
          console.log(`    ${s.name.padEnd(24)} ${s.type.padEnd(10)} # ${s.reason}`);
        }
      }

      if (suggestions.medium.length > 0) {
        console.log('');
        console.log('  Medium confidence:');
        for (const s of suggestions.medium) {
          console.log(`    ${s.name.padEnd(24)} ${s.type.padEnd(10)} # ${s.reason}`);
        }
      }

      if (suggestions.skipped.length > 0) {
        const skippedWarnings = suggestions.skipped.reduce((n, s) => n + s.count, 0);
        console.log('');
        console.log(`  Skipped (${suggestions.skipped.length} variables, ${skippedWarnings} warnings):`);
        for (const s of suggestions.skipped) {
          console.log(`    ${s.name.padEnd(24)} # ${s.reason}`);
        }
      }

      // Write to config file
      const configPath = join(APP_ROOT, 'config/ruby2js.yml');
      const newHints = {};
      for (const s of [...suggestions.high, ...suggestions.medium]) {
        newHints[s.name] = s.type;
      }

      let existingConfig = {};
      if (existsSync(configPath) && yaml) {
        try {
          existingConfig = yaml.load(readFileSync(configPath, 'utf8')) || {};
        } catch { /* ignore parse errors */ }
      }

      // Merge: existing entries take precedence (user corrections not overwritten)
      const existingHints = existingConfig.lint?.type_hints || {};
      const mergedHints = { ...newHints, ...existingHints };

      if (Object.keys(mergedHints).length > 0) {
        if (!existingConfig.lint) existingConfig.lint = {};
        existingConfig.lint.type_hints = mergedHints;

        if (yaml) {
          // Ensure config directory exists
          const configDir = join(APP_ROOT, 'config');
          if (!existsSync(configDir)) mkdirSync(configDir, { recursive: true });

          writeFileSync(configPath, yaml.dump(existingConfig, { lineWidth: -1 }));
          console.log('');
          console.log(`Written to ${relative(APP_ROOT, configPath)} (lint.type_hints section)`);
        } else {
          console.log('');
          console.log('Warning: js-yaml not available, cannot write config file.');
          console.log('Add the following to config/ruby2js.yml manually:');
          console.log('');
          console.log('lint:');
          console.log('  type_hints:');
          for (const [name, type] of Object.entries(mergedHints)) {
            console.log(`    ${name}: ${type}`);
          }
        }
      }
    } else {
      console.log('');
      console.log('No type hint suggestions could be generated from the current warnings.');
    }
  }

  if (totalErrors > 0) {
    process.exit(1);
  }
}

/**
 * Analyze lint diagnostics and suggest type hints based on usage patterns.
 *
 * @param {Array} diagnostics - All collected diagnostic objects
 * @returns {{ high: Array, medium: Array, skipped: Array }} Categorized suggestions
 */
function suggestTypeHints(diagnostics) {
  // Collect all ambiguous_method warnings grouped by receiver name
  const byName = new Map();
  for (const d of diagnostics) {
    if (d.rule !== 'ambiguous_method' || !d.receiver_name) continue;
    const name = d.receiver_name;
    if (!byName.has(name)) byName.set(name, { methods: new Set(), argTypes: [], count: 0 });
    const entry = byName.get(name);
    entry.methods.add(d.method);
    entry.count++;
    if (d.arg_types) entry.argTypes.push(...d.arg_types);
  }

  const high = [];
  const medium = [];
  const skipped = [];

  // Name-based patterns for number detection
  const numberSuffixes = /_(?:count|total|size|seats|score|index|id|number|level|base|amount|price|quantity|weight|height|width|depth|length|offset|limit|max|min|sum|avg|rate|ratio|percent|position|rank|order|step|threshold)$/;

  for (const [name, { methods, argTypes, count }] of byName) {
    const methodArr = [...methods];

    // --- High confidence rules ---

    // Only << methods → array (string << is rare in modern Ruby)
    if (methodArr.length === 1 && methods.has('<<')) {
      high.push({ name, type: 'array', count, reason: 'only used with <<' });
      continue;
    }

    // Only & or | methods → array (bitwise ops on objects are rare)
    if (methodArr.every(m => m === '&' || m === '|')) {
      high.push({ name, type: 'array', count, reason: 'only used with & or |' });
      continue;
    }

    // dup + any array method (<<, +) → array
    if (methods.has('dup') && (methods.has('<<') || (methods.has('+') && methods.has('&')))) {
      high.push({ name, type: 'array', count, reason: 'dup + array operations' });
      continue;
    }

    // delete + << on same var → array (hash doesn't use <<)
    if (methods.has('delete') && methods.has('<<')) {
      high.push({ name, type: 'array', count, reason: 'delete + << (hash does not use <<)' });
      continue;
    }

    // Name matches number suffix patterns
    if (numberSuffixes.test(name)) {
      high.push({ name, type: 'number', count, reason: `name pattern: *_${name.match(numberSuffixes)[0].slice(1)}` });
      continue;
    }

    // Name is 'params' → hash (Rails convention)
    if (name === 'params') {
      high.push({ name, type: 'hash', count, reason: 'Rails convention' });
      continue;
    }

    // --- Medium confidence rules ---

    // Only +/- methods (no array indicators like <<, &, |) → number
    if (methodArr.every(m => m === '+' || m === '-') && !methods.has('<<')) {
      medium.push({ name, type: 'number', count, reason: 'only +/- operations' });
      continue;
    }

    // Only delete (no <<) → hash (hash delete is more common)
    if (methodArr.length === 1 && methods.has('delete') && !methods.has('<<')) {
      medium.push({ name, type: 'hash', count, reason: 'only delete operations' });
      continue;
    }

    // dup alone → hash (hash dup is common in Rails)
    if (methodArr.length === 1 && methods.has('dup')) {
      medium.push({ name, type: 'hash', count, reason: 'only dup (common for hashes)' });
      continue;
    }

    // --- Low confidence: skip ---
    const methodList = methodArr.sort().join(', ');
    skipped.push({ name, count, reason: `mixed ${methodList} — add pragma or type hint manually` });
  }

  // Sort each category by count descending
  high.sort((a, b) => b.count - a.count);
  medium.sort((a, b) => b.count - a.count);
  skipped.sort((a, b) => b.count - a.count);

  return { high, medium, skipped };
}

// ============================================
// Command: info
// ============================================

function runInfo(options) {
  loadEnvLocal();
  loadDatabaseConfig(options);

  const env = options.environment || process.env.RAILS_ENV || 'development';

  console.log('Juntos Configuration');
  console.log('========================================\n');

  console.log('Environment:');
  console.log(`  RAILS_ENV:        ${env}`);
  console.log(`  JUNTOS_DATABASE:  ${process.env.JUNTOS_DATABASE || '(not set)'}`);
  console.log(`  JUNTOS_TARGET:    ${process.env.JUNTOS_TARGET || '(not set)'}`);
  console.log();

  console.log('Database Configuration:');
  console.log(`  Adapter:  ${options.database}`);
  console.log(`  Database: ${options.dbName}`);
  if (options.target) console.log(`  Target:   ${options.target}`);
  console.log();

  console.log('Project:');
  console.log(`  Directory:    ${basename(APP_ROOT)}`);
  console.log(`  Rails app:    ${existsSync(join(APP_ROOT, 'app')) ? 'Yes' : 'No'}`);
  console.log(`  node_modules: ${existsSync(join(APP_ROOT, 'node_modules')) ? 'Installed' : 'Not installed'}`);
  console.log(`  dist/:        ${existsSync(join(APP_ROOT, 'dist')) ? 'Built' : 'Not built'}`);
}

// ============================================
// Command: doctor
// ============================================

function runDoctor(options) {
  console.log('Juntos Doctor');
  console.log('========================================\n');

  let allOk = true;

  // Check Node.js
  try {
    const nodeVersion = execSync('node --version', { encoding: 'utf-8' }).trim();
    const major = parseInt(nodeVersion.slice(1).split('.')[0], 10);
    if (major >= 18) {
      console.log(`Checking Node.js... OK (${nodeVersion})`);
    } else {
      console.log(`Checking Node.js... WARNING (${nodeVersion}, 18+ recommended)`);
    }
  } catch (e) {
    console.log('Checking Node.js... FAILED (not found)');
    allOk = false;
  }

  // Check npm
  try {
    const npmVersion = execSync('npm --version', { encoding: 'utf-8' }).trim();
    console.log(`Checking npm... OK (${npmVersion})`);
  } catch (e) {
    console.log('Checking npm... FAILED (not found)');
    allOk = false;
  }

  // Check Rails app structure
  if (existsSync(join(APP_ROOT, 'app')) && existsSync(join(APP_ROOT, 'config'))) {
    console.log('Checking Rails app structure... OK');
  } else {
    console.log('Checking Rails app structure... FAILED (app/ or config/ missing)');
    allOk = false;
  }

  // Check database.yml
  if (existsSync(join(APP_ROOT, 'config/database.yml'))) {
    console.log('Checking config/database.yml... OK');
  } else {
    console.log('Checking config/database.yml... WARNING (not found)');
  }

  // Check node_modules
  if (existsSync(join(APP_ROOT, 'node_modules'))) {
    console.log('Checking node_modules... OK');
  } else {
    console.log('Checking node_modules... FAILED (run npm install)');
    allOk = false;
  }

  // Check vite.config.js
  if (existsSync(join(APP_ROOT, 'vite.config.js'))) {
    console.log('Checking vite.config.js... OK');
  } else {
    console.log('Checking vite.config.js... WARNING (not found)');
  }

  console.log('\n========================================');
  if (allOk) {
    console.log('All checks passed! Your environment is ready.');
  } else {
    console.log('Some checks failed. Please fix the issues above.');
    process.exit(1);
  }
}

// ============================================
// Command: test
// ============================================

async function runTest(options, testArgs) {
  validateRailsApp();
  loadDatabaseConfig(options);
  validateDatabaseTarget(options);
  ensurePackagesInstalled(options);
  applyEnvOptions(options);

  // Transpile Ruby test files to .test.mjs before running vitest
  const { loadConfig } = await import('./vite.mjs');
  const config = loadConfig(APP_ROOT, {
    database: options.database,
    target: options.target
  });
  await transpileTestFiles(APP_ROOT, config);

  // Ensure vitest is installed
  if (!isPackageInstalled('vitest')) {
    console.log('Installing vitest...');
    try {
      execSync('npm install vitest', {
        cwd: APP_ROOT,
        stdio: 'inherit'
      });
    } catch (e) {
      console.error('Failed to install vitest.');
      process.exit(1);
    }
  }

  // Ensure jsdom is installed (default test environment)
  if (!isPackageInstalled('jsdom')) {
    console.log('Installing jsdom (required by test environment)...');
    try {
      execSync('npm install jsdom', { cwd: APP_ROOT, stdio: 'inherit' });
    } catch (e) {
      console.error('Failed to install jsdom.');
      process.exit(1);
    }
  }

  // Build vitest command
  const args = ['vitest', 'run'];

  // Pass through any additional arguments (file patterns, etc.)
  if (testArgs && testArgs.length > 0) {
    args.push(...testArgs);
  }

  console.log('Running tests...');
  const result = spawnSync('npx', args, {
    cwd: APP_ROOT,
    stdio: 'inherit',
    env: process.env
  });

  process.exit(result.status || 0);
}

// ============================================
// Command: e2e
// ============================================

async function transpileE2EFiles(appRoot, config) {
  const systemTestDir = join(appRoot, 'test', 'system');
  if (!existsSync(systemTestDir)) return 0;
  const files = findRubyTestFiles(systemTestDir);
  if (files.length === 0) return 0;

  const { metadata } = await buildAppManifest(appRoot, config, { mode: 'virtual' });
  metadata.playwright = true;

  let count = 0;
  for (const file of files) {
    const outName = file.replace(/_test\.rb$/, '.spec.mjs');
    const outPath = join(systemTestDir, outName);

    // Skip if .spec.mjs is newer than _test.rb
    if (existsSync(outPath)) {
      const rbStat = statSync(join(systemTestDir, file));
      const mjsStat = statSync(outPath);
      if (mjsStat.mtimeMs > rbStat.mtimeMs) continue;
    }

    try {
      const source = readFileSync(join(systemTestDir, file), 'utf-8');
      metadata.fixture_plan = null;
      const result = await transformRuby(source, join(systemTestDir, file), 'test', config, appRoot, metadata);
      let code = result.code;

      // Skip empty test suites (no test() calls)
      if (!/\btest\s*\(/.test(code)) {
        if (existsSync(outPath)) unlinkSync(outPath);
        continue;
      }

      writeFileSync(outPath, code);
      count++;
    } catch (err) {
      console.warn(`  Warning: Failed to transpile ${file}: ${err.message}`);
    }
  }

  if (count > 0) {
    console.log(`Transpiled ${count} e2e test file${count > 1 ? 's' : ''}.`);
  }
  return count;
}

function generatePlaywrightConfig(appRoot) {
  const configPath = join(appRoot, 'playwright.config.js');
  if (existsSync(configPath)) return;

  const config = `import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "./test/system",
  testMatch: "**/*.spec.mjs",
  use: {
    baseURL: "http://localhost:5173"
  },
  webServer: {
    command: "npx juntos dev",
    url: "http://localhost:5173",
    reuseExistingServer: !process.env.CI
  }
});
`;
  writeFileSync(configPath, config);
  console.log('Generated playwright.config.js');
}

async function runE2E(options, e2eArgs) {
  validateRailsApp();
  loadDatabaseConfig(options);
  validateDatabaseTarget(options);
  ensurePackagesInstalled(options);
  applyEnvOptions(options);

  const { loadConfig } = await import('./vite.mjs');
  const config = loadConfig(APP_ROOT, {
    database: options.database,
    target: options.target
  });
  await transpileE2EFiles(APP_ROOT, config);

  // Auto-install @playwright/test if needed
  if (!isPackageInstalled('@playwright/test')) {
    console.log('Installing @playwright/test...');
    try {
      execSync('npm install @playwright/test', {
        cwd: APP_ROOT,
        stdio: 'inherit'
      });
    } catch (e) {
      console.error('Failed to install @playwright/test.');
      process.exit(1);
    }

    console.log('Installing Playwright browsers...');
    try {
      execSync('npx playwright install --with-deps chromium', {
        cwd: APP_ROOT,
        stdio: 'inherit'
      });
    } catch (e) {
      console.error('Failed to install Playwright browsers.');
      process.exit(1);
    }
  }

  // Generate playwright.config.js if missing
  generatePlaywrightConfig(APP_ROOT);

  // Run: npx playwright test [args]
  console.log('Running e2e tests...');
  const result = spawnSync('npx', ['playwright', 'test', ...e2eArgs], {
    cwd: APP_ROOT,
    stdio: 'inherit',
    env: process.env
  });

  process.exit(result.status || 0);
}

// ============================================
// Command: deploy
// ============================================

const DEPLOY_TARGETS = {
  vercel: ['turso', 'neon', 'planetscale', 'supabase', 'dexie'],
  'vercel-edge': ['turso', 'neon', 'planetscale', 'supabase'],
  cloudflare: ['d1', 'turso', 'dexie'],
  'deno-deploy': ['turso', 'neon', 'dexie']
};

function runDeploy(options) {
  validateRailsApp();
  loadEnvLocal();
  loadDatabaseConfig(options);
  validateDatabaseTarget(options);
  ensurePackagesInstalled(options);

  // Default to production environment for deploy
  options.environment = options.environment || 'production';
  process.env.RAILS_ENV = options.environment;
  process.env.NODE_ENV = 'production';

  // Infer target from database if not specified
  if (!options.target && options.database) {
    if (options.database === 'd1') options.target = 'cloudflare';
    else if (['neon', 'turso', 'planetscale', 'supabase'].includes(options.database)) options.target = 'vercel';
  }

  if (!options.target) {
    console.error('Error: Deploy target required.');
    console.error('Use -t/--target to specify: vercel, cloudflare');
    console.error('\nExample: juntos deploy -t cloudflare -d d1');
    process.exit(1);
  }

  if (!DEPLOY_TARGETS[options.target]) {
    console.error(`Error: Unknown target '${options.target}'.`);
    console.error('Valid targets: vercel, cloudflare');
    process.exit(1);
  }

  if (options.database) {
    const validDbs = DEPLOY_TARGETS[options.target];
    if (!validDbs.includes(options.database)) {
      console.error(`Error: Database '${options.database}' not supported for ${options.target}.`);
      console.error(`Valid databases: ${validDbs.join(', ')}`);
      process.exit(1);
    }
  }

  applyEnvOptions(options);

  // Generate platform entry point BEFORE build (Vite needs it)
  if (options.target === 'cloudflare') {
    generateCloudflareEntryPoint(options);
  } else if (options.target === 'vercel' || options.target === 'vercel-edge') {
    generateVercelEntryPoint(options);
  } else if (options.target === 'deno-deploy') {
    generateDenoDeployEntryPoint(options);
  }

  // Build first unless skipped
  if (!options.skipBuild) {
    console.log(`Building for ${options.target} (${options.environment})...`);
    try {
      const buildArgs = ['vite', 'build'];
      if (options.sourcemap) buildArgs.push('--sourcemap');
      execSync(`npx ${buildArgs.join(' ')}`, { cwd: APP_ROOT, stdio: 'inherit', env: process.env });
    } catch (e) {
      console.error('Build failed.');
      process.exit(1);
    }
  }

  // Generate platform config (after build, in dist/)
  if (options.target === 'cloudflare') {
    generateCloudflareConfig(options);
  } else if (options.target === 'vercel') {
    generateVercelConfig(options);
  }

  // Run platform deploy
  runPlatformDeploy(options);
}

function generateCloudflareEntryPoint(options) {
  // Generate Worker entry point in src/ BEFORE build
  // This is needed because Vite requires the entry point to exist
  const srcDir = join(APP_ROOT, 'src');
  if (!existsSync(srcDir)) {
    mkdirSync(srcDir, { recursive: true });
  }

  // Check if app uses Turbo broadcasting
  const usesBroadcasting = checkUsesBroadcasting();

  const imports = usesBroadcasting
    ? "import { Application, Router, TurboBroadcaster } from 'juntos:rails';"
    : "import { Application, Router } from 'juntos:rails';";

  const exports = usesBroadcasting
    ? "export default Application.worker();\nexport { TurboBroadcaster };"
    : "export default Application.worker();";

  // Use virtual modules - Vite transforms these at build time
  const workerJs = `// Cloudflare Worker entry point
// Generated by Juntos

${imports}
import '../config/routes.rb';
import { migrations } from 'juntos:migrations';
import { Seeds } from '../db/seeds.rb';
import { layout } from 'juntos:views/layouts';

// Configure application
Application.configure({
  migrations: migrations,
  seeds: Seeds,
  layout: layout
});

${exports}
`;

  writeFileSync(join(srcDir, 'index.js'), workerJs);
  console.log('  Generated src/index.js (worker entry point)');
}

function generateDenoDeployEntryPoint(options) {
  // Generate Deno Deploy entry point as main.ts
  const entryTs = `// Deno Deploy entry point
// Generated by Juntos

import { Application, Router } from 'juntos:rails';
import './config/routes.rb';
import { migrations } from 'juntos:migrations';
import { Seeds } from './db/seeds.rb';
import { layout } from 'juntos:views/layouts';

// Configure application
Application.configure({
  migrations: migrations,
  seeds: Seeds,
  layout: layout
});

Deno.serve(Application.handler());
`;

  writeFileSync(join(APP_ROOT, 'main.ts'), entryTs);
  console.log('  Generated main.ts (Deno Deploy entry point)');
}

function generateVercelEntryPoint(options) {
  // Generate Vercel Edge Function entry point in api/ BEFORE build
  const apiDir = join(APP_ROOT, 'api');
  if (!existsSync(apiDir)) {
    mkdirSync(apiDir, { recursive: true });
  }

  const isEdge = options.target === 'vercel-edge';

  // Use virtual modules - Vite transforms these at build time
  const entryJs = `// Vercel ${isEdge ? 'Edge' : 'Node'} Function entry point
// Generated by Juntos

import { Application, Router } from 'juntos:rails';
import '../config/routes.rb';
import { migrations } from 'juntos:migrations';
import { Seeds } from '../db/seeds.rb';
import { layout } from 'juntos:views/layouts';

// Configure application
Application.configure({
  migrations: migrations,
  seeds: Seeds,
  layout: layout
});

${isEdge ? `export const config = { runtime: 'edge' };` : ''}

export default Application.handler();
`;

  writeFileSync(join(apiDir, '[[...path]].js'), entryJs);
  console.log('  Generated api/[[...path]].js (Vercel entry point)');
}

function generateCloudflareConfig(options) {
  const appName = basename(APP_ROOT).toLowerCase().replace(/[^a-z0-9-]/g, '-');
  const env = options.environment || 'production';
  const dbName = options.dbName || `${appName}_${env}`.toLowerCase().replace(/[^a-z0-9_]/g, '_');

  // Get D1 database ID
  const envVar = env === 'development' ? 'D1_DATABASE_ID' : `D1_DATABASE_ID_${env.toUpperCase()}`;
  const d1DatabaseId = process.env[envVar] || process.env.D1_DATABASE_ID;

  if (!d1DatabaseId && options.database === 'd1') {
    console.error(`Error: ${envVar} not found.`);
    console.error('Set it in .env.local or as an environment variable.');
    console.error(`\nCreate with: juntos db:create -d d1 -e ${env}`);
    process.exit(1);
  }

  // Check if app uses Turbo broadcasting
  const usesBroadcasting = checkUsesBroadcasting();

  let wranglerToml = `name = "${appName}"
main = "worker.js"
compatibility_date = "${new Date().toISOString().split('T')[0]}"
compatibility_flags = ["nodejs_compat"]
workers_dev = true
preview_urls = true

# D1 database binding
[[d1_databases]]
binding = "DB"
database_name = "${dbName}"
database_id = "${d1DatabaseId}"

# Static assets (Rails convention: public/)
[assets]
directory = "./public"
`;

  if (usesBroadcasting) {
    wranglerToml += `
# Durable Objects for Turbo Streams broadcasting
[[durable_objects.bindings]]
name = "TURBO_BROADCASTER"
class_name = "TurboBroadcaster"

[[migrations]]
tag = "v1"
new_sqlite_classes = ["TurboBroadcaster"]
`;
  }

  const distDir = join(APP_ROOT, 'dist');
  writeFileSync(join(distDir, 'wrangler.toml'), wranglerToml);
  console.log('  Generated wrangler.toml');

  // Generate Worker entry point
  const srcDir = join(distDir, 'src');
  if (!existsSync(srcDir)) {
    mkdirSync(srcDir, { recursive: true });
  }

  const imports = usesBroadcasting
    ? "import { Application, Router, TurboBroadcaster } from '../lib/rails.js';"
    : "import { Application, Router } from '../lib/rails.js';";

  const exports = usesBroadcasting
    ? "export default Application.worker();\nexport { TurboBroadcaster };"
    : "export default Application.worker();";

  const workerJs = `// Cloudflare Worker entry point
// Generated by Juntos

${imports}
import '../config/routes.js';
import { migrations } from '../db/migrate/index.js';
import { Seeds } from '../db/seeds.js';
import { layout } from '../app/views/layouts/application.js';

// Configure application
Application.configure({
  migrations: migrations,
  seeds: Seeds,
  layout: layout
});

${exports}
`;

  writeFileSync(join(srcDir, 'index.js'), workerJs);
  console.log('  Generated src/index.js');
}

function generateVercelConfig(options) {
  const vercelJson = {
    version: 2,
    buildCommand: "",
    routes: [
      { src: "/assets/(.*)", dest: "/public/assets/$1" },
      { src: "/(.*)", dest: "/api/[[...path]]" }
    ]
  };

  if (options.force) {
    vercelJson.installCommand = "npm cache clean --force && npm install";
  }

  const distDir = join(APP_ROOT, 'dist');
  writeFileSync(join(distDir, 'vercel.json'), JSON.stringify(vercelJson, null, 2));
  console.log('  Generated vercel.json');
}

function checkUsesBroadcasting() {
  const modelsDir = join(APP_ROOT, 'app/models');
  const viewsDir = join(APP_ROOT, 'app/views');

  // Check models for broadcast_*_to calls
  if (existsSync(modelsDir)) {
    try {
      const files = execSync(`find ${modelsDir} -name "*.rb"`, { encoding: 'utf-8' }).trim().split('\n');
      for (const file of files) {
        if (file && existsSync(file)) {
          const content = readFileSync(file, 'utf-8');
          if (/broadcast_\w+_to/.test(content)) return true;
        }
      }
    } catch (e) {}
  }

  // Check views for turbo_stream_from helper
  if (existsSync(viewsDir)) {
    try {
      const files = execSync(`find ${viewsDir} -name "*.erb"`, { encoding: 'utf-8' }).trim().split('\n');
      for (const file of files) {
        if (file && existsSync(file)) {
          const content = readFileSync(file, 'utf-8');
          if (/turbo_stream_from/.test(content)) return true;
        }
      }
    } catch (e) {}
  }

  return false;
}

function runPlatformDeploy(options) {
  console.log(`\nDeploying to ${options.target}...`);

  const distDir = join(APP_ROOT, 'dist');

  if (options.target === 'cloudflare') {
    try {
      execSync('which wrangler', { stdio: 'ignore' });
      console.log('Running: wrangler deploy');
      execSync('wrangler deploy', { cwd: distDir, stdio: 'inherit' });
    } catch (e) {
      if (e.status === undefined) {
        console.log('\nTo deploy, install Wrangler and run:');
        console.log('  npm install -g wrangler');
        console.log('  cd dist && wrangler deploy');
      } else {
        console.error('Deploy failed.');
        process.exit(1);
      }
    }
  } else if (options.target === 'vercel') {
    try {
      execSync('which vercel', { stdio: 'ignore' });
      const args = ['vercel', '--prod'];
      if (options.force) args.push('--force');
      console.log(`Running: ${args.join(' ')}`);
      execSync(args.join(' '), { cwd: distDir, stdio: 'inherit' });
    } catch (e) {
      if (e.status === undefined) {
        console.log('\nTo deploy, install Vercel CLI and run:');
        console.log('  npm install -g vercel');
        console.log('  cd dist && vercel --prod');
      } else {
        console.error('Deploy failed.');
        process.exit(1);
      }
    }
  }
}

// ============================================
// Main help
// ============================================

function showHelp() {
  console.log(`
Juntos - Rails patterns, JavaScript runtimes

Usage: juntos [options] <command> [command-options]

Commands:
  init      Initialize Juntos in a project
  dev       Start development server with hot reload
  build     Build for deployment
  eject     Write transpiled JavaScript files to disk (for debugging/migration)
  test      Run tests with Vitest
  e2e       Run end-to-end tests with Playwright
  server    Start production server (requires prior build)
  deploy    Build and deploy to serverless platform
  up        Build and run locally (node, bun, browser)
  db        Database commands (create, migrate, seed, prepare, drop, reset)
  lint      Scan Ruby files for transpilation issues
  info      Show current configuration
  doctor    Check environment and prerequisites

Common Options:
  -d, --database ADAPTER   Database adapter (dexie, sqlite, d1, etc.)
  -e, --environment ENV    Environment (development, production, test)
  -t, --target TARGET      Deploy target (browser, node, vercel, cloudflare)
  -p, --port PORT          Server port (default: 3000)

Examples:
  juntos dev                           # Start dev server (uses database.yml)
  juntos dev -d dexie                  # Dev with IndexedDB
  juntos build                         # Build for deployment
  juntos test                          # Run all tests
  juntos test -d sqlite                # Run tests with SQLite
  juntos up -d sqlite                  # Build and run with SQLite
  juntos deploy -t cloudflare -d d1    # Deploy to Cloudflare with D1
  juntos deploy -t vercel -d neon      # Deploy to Vercel with Neon
  juntos db:prepare                    # Migrate and seed if fresh
  juntos db:migrate -d d1              # Migrate D1 database

Run 'juntos <command> --help' for command-specific options.
`);
}

// ============================================
// Main entry point
// ============================================

const args = process.argv.slice(2);
const { options, remaining, passthrough } = parseCommonArgs(args);

let command = remaining[0];
const commandArgs = remaining.slice(1);

// Handle db:command syntax
if (command && command.includes(':')) {
  const [cmd, subcmd] = command.split(':', 2);
  command = cmd;
  commandArgs.unshift(subcmd);
}

if (!command || options.help && !command) {
  showHelp();
  process.exit(command ? 0 : 1);
}

switch (command) {
  case 'init':
    if (options.help) {
      console.log('Usage: juntos init [options]\n\nInitialize Juntos in a project.\n');
      console.log('Options:');
      console.log('  --no-install   Skip npm install');
      console.log('  --quiet        Suppress output');
      process.exit(0);
    }
    // Parse --no-install flag
    options.noInstall = process.argv.includes('--no-install');
    options.quiet = process.argv.includes('--quiet');
    runInit(options);
    break;

  case 'dev':
    if (options.help) {
      console.log('Usage: juntos dev [options] [-- vite-args...]\n\nStart development server with hot reload.\n');
      console.log('Options:');
      console.log('  -d, --database ADAPTER   Database adapter');
      console.log('  -p, --port PORT          Server port (default: 5173)');
      console.log('  -o, --open               Open browser automatically');
      console.log('  --host, --binding        Listen on all interfaces (0.0.0.0)');
      console.log('\nAny arguments after -- are passed directly to Vite.');
      process.exit(0);
    }
    runDev(options, passthrough);
    break;

  case 'build':
    if (options.help) {
      console.log('Usage: juntos build [options] [-- vite-args...]\n\nBuild application for deployment.\n');
      console.log('Options:');
      console.log('  -d, --database ADAPTER   Database adapter');
      console.log('  -t, --target TARGET      Build target');
      console.log('  -e, --environment ENV    Environment');
      console.log('  --sourcemap              Generate source maps');
      console.log('  --base PATH              Base public path for assets');
      console.log('\nAny arguments after -- are passed directly to Vite.');
      process.exit(0);
    }
    runBuild(options, passthrough);
    break;

  case 'eject':
    if (options.help) {
      console.log('Usage: juntos eject [options]\n\nWrite transpiled JavaScript files to disk.\n');
      console.log('This is useful for debugging or migrating away from Ruby source.\n');
      console.log('Options:');
      console.log('  --output, --out DIR      Output directory (default: ejected/)');
      console.log('  -d, --database ADAPTER   Database adapter');
      console.log('  -t, --target TARGET      Build target');
      console.log('  --base PATH              Base public path');
      console.log('\nFiltering:');
      console.log('  --include PATTERN        Include only matching files (can be repeated)');
      console.log('  --exclude PATTERN        Exclude matching files (can be repeated)');
      console.log('  --only FILES             Comma-separated list of files to include');
      console.log('\nPatterns support glob syntax: * (any), ** (any including /), ? (single char)');
      console.log('\nExamples:');
      console.log('  juntos eject --include "app/models/*.rb"');
      console.log('  juntos eject --include "app/views/articles/**/*" --exclude "**/test_*"');
      console.log('  juntos eject --only app/models/article.rb,app/models/comment.rb');
      console.log('\nFiltering can also be configured in config/ruby2js.yml:');
      console.log('  eject:');
      console.log('    include: [app/models/*.rb, app/views/articles/**/*]');
      console.log('    exclude: ["**/test_*"]');
      console.log('\nDebugging:');
      console.log('  DEBUG=1 juntos eject     Show full stack traces and check JS syntax');
      process.exit(0);
    }
    runEject(options).catch(err => {
      console.error('Eject failed:', formatError(err));
      process.exit(1);
    });
    break;

  case 'up':
    if (options.help) {
      console.log('Usage: juntos up [options]\n\nBuild and run locally.\n');
      console.log('Options:');
      console.log('  -d, --database ADAPTER   Database adapter');
      console.log('  -t, --target TARGET      Runtime target (browser, node, bun)');
      console.log('  -p, --port PORT          Server port (default: 3000)');
      console.log('  --host, --binding        Listen on all interfaces (0.0.0.0)');
      process.exit(0);
    }
    runUp(options);
    break;

  case 'server':
    if (options.help) {
      console.log('Usage: juntos server [options]\n\nStart production server (requires prior build).\n');
      console.log('Options:');
      console.log('  -t, --target TARGET      Runtime target (browser, node, bun, deno)');
      console.log('  -p, --port PORT          Server port (default: 3000)');
      console.log('  -e, --environment ENV    Environment (default: production)');
      console.log('  --host, --binding        Listen on all interfaces (0.0.0.0)');
      process.exit(0);
    }
    runServer(options);
    break;

  case 'db':
    runDb(commandArgs, options);
    break;

  case 'lint':
    if (options.help) {
      console.log('Usage: juntos lint [options] [files...]\n\nScan Ruby files for transpilation issues.\n');
      console.log('Options:');
      console.log('  --strict                 Enable strict warnings (rare but possible issues)');
      console.log('  --summary                Show untyped variable summary (for type hints)');
      console.log('  --suggest                Auto-generate type hints in config/ruby2js.yml');
      console.log('  --disable RULE           Disable a lint rule (can be repeated)');
      console.log('  --include PATTERN        Include only matching files (glob)');
      console.log('  --exclude PATTERN        Exclude matching files (glob)');
      console.log('\nRules:');
      console.log('  ambiguous_method   Method with different JS behavior depending on type');
      console.log('  method_missing     method_missing cannot be transpiled');
      console.log('  eval_call          eval() is not safely transpilable');
      console.log('  instance_eval      instance_eval is not transpilable');
      console.log('  singleton_method   def obj.method on non-self receiver has limited support');
      console.log('  retry_statement    retry has no JS equivalent');
      console.log('  redo_statement     redo has no JS equivalent');
      console.log('  ruby_catch_throw   Ruby catch/throw differs from JS');
      console.log('  prepend_call       prepend has no JS equivalent');
      console.log('  force_encoding     force_encoding has no JS equivalent');
      console.log('  parse_error        File could not be parsed');
      console.log('  conversion_error   File could not be converted');
      console.log('\nExamples:');
      console.log('  juntos lint                              # Lint all Ruby source files');
      console.log('  juntos lint app/models/article.rb        # Lint specific file');
      console.log('  juntos lint --strict                     # Include strict warnings');
      console.log('  juntos lint --disable ambiguous_method   # Skip ambiguity warnings');
      console.log('  juntos lint --suggest                    # Auto-generate type hints');
      process.exit(0);
    }
    runLint(commandArgs, options).catch(err => {
      console.error('Lint failed:', formatError(err));
      process.exit(1);
    });
    break;

  case 'info':
    runInfo(options);
    break;

  case 'doctor':
    runDoctor(options);
    break;

  case 'test':
    if (options.help) {
      console.log('Usage: juntos test [options] [files...]\n\nRun tests with Vitest.\n');
      console.log('Options:');
      console.log('  -d, --database ADAPTER   Database adapter for tests');
      console.log('\nExamples:');
      console.log('  juntos test                    # Run all tests');
      console.log('  juntos test articles.test.mjs  # Run specific test file');
      console.log('  juntos test -d sqlite          # Run tests with SQLite');
      process.exit(0);
    }
    runTest(options, commandArgs).catch(err => {
      console.error(`Test failed: ${err.message}`);
      process.exit(1);
    });
    break;

  case 'e2e':
    if (options.help) {
      console.log('Usage: juntos e2e [options] [files...]\n\nRun end-to-end tests with Playwright.\n');
      console.log('Options:');
      console.log('  -d, --database ADAPTER   Database adapter for tests');
      console.log('\nExamples:');
      console.log('  juntos e2e                     # Run all e2e tests');
      console.log('  juntos e2e --headed            # Run with visible browser');
      console.log('  juntos e2e --ui                # Open Playwright UI mode');
      process.exit(0);
    }
    runE2E(options, commandArgs).catch(err => {
      console.error(`E2E tests failed: ${err.message}`);
      process.exit(1);
    });
    break;

  case 'deploy':
    if (options.help) {
      console.log('Usage: juntos deploy [options]\n\nBuild and deploy to a serverless platform.\n');
      console.log('Options:');
      console.log('  -t, --target TARGET      Deploy target (vercel, cloudflare)');
      console.log('  -d, --database ADAPTER   Database adapter');
      console.log('  -e, --environment ENV    Environment (default: production)');
      console.log('  --skip-build             Skip the build step');
      console.log('  -f, --force              Force deploy (clear cache)');
      console.log('  --sourcemap              Generate source maps');
      process.exit(0);
    }
    runDeploy(options);
    break;

  default:
    console.error(`Unknown command: ${command}`);
    console.error("Run 'juntos --help' for usage.");
    process.exit(1);
}
