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
  generateModelsModuleForEject,
  generateMigrationsModuleForEject,
  generateViewsModuleForEject,
  generateApplicationRecordForEject,
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
  fixTestImportsForEject
} from './transform.mjs';

import { singularize, camelize, pluralize, underscore } from './adapters/inflector.mjs';

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

// ============================================
// Glob matching helpers (for eject filtering)
// ============================================

/**
 * Convert a glob pattern to a regex.
 * Supports: * (any non-slash), ** (any including slash), ? (single char)
 */
function globToRegex(pattern) {
  let regex = pattern
    // Escape special regex chars (except * and ?)
    .replace(/[.+^${}()|[\]\\]/g, '\\$&')
    // ** matches anything including /
    .replace(/\*\*/g, '<<<GLOBSTAR>>>')
    // * matches anything except /
    .replace(/\*/g, '[^/]*')
    // ? matches single char except /
    .replace(/\?/g, '[^/]')
    // Restore globstar
    .replace(/<<<GLOBSTAR>>>/g, '.*');

  return new RegExp(`^${regex}$`);
}

/**
 * Check if a path matches any of the given glob patterns.
 */
function matchesAny(filePath, patterns) {
  if (!patterns || patterns.length === 0) return false;
  return patterns.some(pattern => {
    // Normalize path separators
    const normalizedPath = filePath.replace(/\\/g, '/');
    const normalizedPattern = pattern.replace(/\\/g, '/');
    return globToRegex(normalizedPattern).test(normalizedPath);
  });
}

/**
 * Determine if a file should be included in eject based on include/exclude patterns.
 *
 * @param {string} relativePath - Path relative to app root (e.g., 'app/models/article.rb')
 * @param {string[]} includePatterns - Patterns to include (if empty, include all)
 * @param {string[]} excludePatterns - Patterns to exclude
 * @returns {boolean} True if file should be included
 */
function shouldIncludeFile(relativePath, includePatterns, excludePatterns) {
  // Normalize path
  const normalizedPath = relativePath.replace(/\\/g, '/');

  // If include patterns specified, file must match at least one
  if (includePatterns && includePatterns.length > 0) {
    if (!matchesAny(normalizedPath, includePatterns)) {
      return false;
    }
  }

  // If exclude patterns specified, file must not match any
  if (excludePatterns && excludePatterns.length > 0) {
    if (matchesAny(normalizedPath, excludePatterns)) {
      return false;
    }
  }

  return true;
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
// Concern merging for model transpilation
// ============================================

/**
 * Extract the body of `included do ... end` from a concern file.
 * Returns the lines inside the block, or empty string if not found.
 */
function extractIncludedDoBody(concernSource) {
  // Match `included do\n ... \n  end` — the `end` that closes `included do`
  // is at the same indentation level as `included`
  const match = concernSource.match(/^(\s*)included\s+do\s*\n([\s\S]*?)\n\1end/m);
  if (!match) return '';
  return match[2];
}

/**
 * Pre-process a model's Ruby source to merge in declarations from its
 * included concerns' `included do` blocks.
 *
 * This ensures that `has_many`, `belongs_to`, `has_one`, `scope`, `enum`,
 * and callback declarations that live in concerns are visible to the
 * Rails model filter during transpilation.
 *
 * @param {string} source - The model's Ruby source code
 * @param {string} modelsDir - Path to app/models directory
 * @returns {string} Modified source with concern declarations injected
 */
function mergeConcernDeclarations(source, modelsDir) {
  // Find the class declaration and its include statement
  const classMatch = source.match(/^(class\s+(\w+)\s*<[^\n]*\n)/m);
  if (!classMatch) return source;
  const className = classMatch[2];

  // Find include statements: `include Foo, Bar, Baz` (may span multiple lines)
  const includeRegex = /^\s*include\s+([\s\S]*?)(?=\n\s*(?:[a-z]|#|$|\n|include\s))/gm;
  let includeMatch;
  const concernNames = [];
  while ((includeMatch = includeRegex.exec(source)) !== null) {
    // Flatten continuation lines and split comma-separated concern names
    const flat = includeMatch[1].replace(/\n\s*/g, ' ').replace(/#.*/, '');
    const names = flat.split(',').map(n => n.trim()).filter(n => /^[A-Z]/.test(n));
    concernNames.push(...names);
  }

  // Track which concern files we've already processed (from explicit includes)
  const processedFiles = new Set();

  // Shared concerns directory: app/models/concerns/
  const concernsDir = join(modelsDir, '..', 'models', 'concerns');

  // Helper: extract declarations from a concern file's included-do block
  // Also follows include ::ModuleName chains to shared concerns
  function extractDeclarationsFromFile(filePath) {
    const lines = [];
    try {
      const concernSource = readFileSync(filePath, 'utf-8');
      const body = extractIncludedDoBody(concernSource);

      // Follow include chains: look for `include ::ModuleName` in the
      // entire concern file (both module body and included-do block)
      const includeChainRegex = /^\s*include\s+::(\w+)/gm;
      let chainMatch;
      while ((chainMatch = includeChainRegex.exec(concernSource)) !== null) {
        const sharedName = chainMatch[1];
        const snaked = sharedName.replace(/([A-Z])/g, (m, c, i) => (i > 0 ? '_' : '') + c.toLowerCase());
        const sharedFile = join(concernsDir, snaked + '.rb');
        if (existsSync(sharedFile) && !processedFiles.has(sharedFile)) {
          processedFiles.add(sharedFile);
          lines.push(...extractDeclarationsFromFile(sharedFile));
        }
      }

      if (body) {
        // Inject declarations that define model structure and behavior:
        // - Associations: has_many, has_one, belongs_to
        // - Scopes and enums: scope, enum
        // - Callbacks: before_save :method, after_create -> { ... }, etc.
        for (const line of body.split('\n')) {
          const trimmed = line.trim();
          if (trimmed.length === 0 || trimmed.startsWith('#')) continue;
          if (/^(has_many|has_one|belongs_to|scope|enum)\b/.test(trimmed)) {
            // Skip multi-line block openers (incomplete without body + end)
            // e.g., "has_many :accesses do", "scope :foo, -> do"
            if (/\bdo\s*(\|[^|]*\|)?\s*$/.test(trimmed)) continue;
            lines.push('  ' + trimmed);
          }
          // Callbacks: merge symbol-based (before_save :method_name),
          // lambda-based (after_create -> { ... }), and simple block callbacks.
          // Skip multi-line blocks (do...end) and callbacks with self.class
          // which don't transpile well in the model callback context.
          if (/^(before_|after_)\w+\b/.test(trimmed)) {
            if (/\bdo\s*(\|[^|]*\|)?\s*$/.test(trimmed)) continue;
            if (/self\.class\b/.test(trimmed)) continue;
            lines.push('  ' + trimmed);
          }
        }
      }
    } catch (err) {
      // Skip concerns that can't be read
    }
    return lines;
  }

  // Phase 1: Process explicitly included concerns
  const injectedLines = [];
  for (const name of concernNames) {
    // Concern file path: Card includes Closeable => card/closeable.rb
    // Board includes Cards => board/cards.rb
    const snakeName = name.replace(/([A-Z])/g, (m, c, i) => (i > 0 ? '_' : '') + c.toLowerCase());
    const concernFile = join(modelsDir, className.toLowerCase(), snakeName + '.rb');

    if (!existsSync(concernFile)) continue;
    processedFiles.add(concernFile);
    injectedLines.push(...extractDeclarationsFromFile(concernFile));
  }

  // Phase 2: Auto-discover concerns from the model's subdirectory
  // Rails convention: files in app/models/card/ are Card:: concerns
  // Some may not be explicitly included (e.g., stripped benchmark repos)
  const modelSubdir = join(modelsDir, className.toLowerCase());
  if (existsSync(modelSubdir)) {
    try {
      for (const entry of readdirSync(modelSubdir, { withFileTypes: true })) {
        if (!entry.isFile() || !entry.name.endsWith('.rb')) continue;
        const filePath = join(modelSubdir, entry.name);
        if (processedFiles.has(filePath)) continue;

        // Only process ActiveSupport::Concern modules (skip sub-models and plain classes)
        try {
          const content = readFileSync(filePath, 'utf-8');
          if (!/extend\s+ActiveSupport::Concern/.test(content)) continue;
          processedFiles.add(filePath);
          injectedLines.push(...extractDeclarationsFromFile(filePath));
        } catch (err) {
          // Skip unreadable files
        }
      }
    } catch (err) {
      // Skip if directory can't be read
    }
  }

  if (injectedLines.length === 0) return source;

  // Inject after the last include statement (handling multi-line includes with
  // continuation lines, and multiple separate include statements)
  const includeLineRegex = /^\s*include\s+[^\n]+(?:\n\s{4,}[^\n]+)*/gm;
  let lastInclude = null;
  let m;
  while ((m = includeLineRegex.exec(source)) !== null) {
    lastInclude = m;
  }
  if (lastInclude) {
    const pos = lastInclude.index + lastInclude[0].length;
    // Find the end of the line (in case the regex stopped mid-line)
    const lineEnd = source.indexOf('\n', pos);
    const insertPos = lineEnd !== -1 ? lineEnd + 1 : pos;
    return source.slice(0, insertPos) + '\n  # [merged from concerns]\n' + injectedLines.join('\n') + '\n' + source.slice(insertPos);
  }

  // Fallback: insert after class declaration
  const classEnd = classMatch.index + classMatch[0].length;
  return source.slice(0, classEnd) + '\n  # [merged from concerns]\n' + injectedLines.join('\n') + '\n' + source.slice(classEnd);
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
function buildFixturePlan(rubySource, fixtures, associationMap) {
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

  if (referencedFixtures.size === 0) return null;

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

  // Reverse resolution: pull in has_one fixtures that point back to collected fixtures
  const collectedByTable = new Map();
  for (const { table, fixture } of allFixtures.values()) {
    if (!collectedByTable.has(table)) collectedByTable.set(table, new Set());
    collectedByTable.get(table).add(fixture);
  }

  const reverseBackRefs = [];

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
          if (!allFixtures.has(childKey)) {
            allFixtures.set(childKey, { table: reverseTable, fixture: revFixtureName });
            const revData = fixtures[reverseTable]?.[revFixtureName];
            if (revData && typeof revData === 'object') {
              for (const [col, val] of Object.entries(revData)) {
                if (typeof val !== 'string') continue;
                const resolved = resolveFixtureValue(val, col, reverseTable, associationMap, fixtures);
                if (resolved) {
                  const depKey = `${resolved.targetTable}_${resolved.ref.fixtureName}`;
                  if (!allFixtures.has(depKey)) {
                    allFixtures.set(depKey, { table: resolved.targetTable, fixture: resolved.ref.fixtureName });
                  }
                }
              }
            }
          }
          reverseBackRefs.push({ parentKey, assocName, childKey });
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

  const setupCode = `beforeEach(async () => {\n${createLines.join('\n')}\n});`;

  // Collect unique model names referenced in fixture creates (for import generation)
  const fixtureModels = [...new Set([...allFixtures.values()].map(f => camelize(singularize(f.table))))];

  return { setupCode, replacements, fixtureModels };
}

/**
 * Parse test_helper.rb for global Current attribute assignments.
 *
 * Looks for patterns like: Current.account = accounts("37s")
 * Returns an array of { attr, table, fixture } objects stored in metadata
 * for the test filter to generate Current setup beforeEach blocks at AST level.
 */
function parseCurrentAttributes(appRoot) {
  const helperPath = join(appRoot, 'test/test_helper.rb');
  const attrs = [];
  if (existsSync(helperPath)) {
    const helper = readFileSync(helperPath, 'utf-8');
    const regex = /Current\.(\w+)\s*=\s*(\w+)\(["'](\w+)["']\)/g;
    let match;
    while ((match = regex.exec(helper)) !== null) {
      attrs.push({ attr: match[1], table: match[2], fixture: match[3] });
    }
  }
  return attrs;
}
// ============================================
// Dev-mode test transpilation (for juntos test)
// ============================================

/**
 * Build association map from Ruby source model files.
 * Parses belongs_to declarations to determine foreign key relationships.
 * Used for fixture inlining when transpiled model files aren't available.
 */
function buildAssociationMapFromRuby(modelsDir) {
  const assocMap = {};
  if (!existsSync(modelsDir)) return assocMap;

  const modelFiles = readdirSync(modelsDir)
    .filter(f => f.endsWith('.rb') && f !== 'application_record.rb');

  for (const file of modelFiles) {
    try {
      let content = readFileSync(join(modelsDir, file), 'utf-8');

      // Merge concern declarations so belongs_to in concerns are found
      content = mergeConcernDeclarations(content, modelsDir);

      // Extract class name
      const classMatch = content.match(/class\s+(\w+)\s*</);
      if (!classMatch) continue;
      const className = classMatch[1];
      const tableName = underscore(pluralize(className));

      // Find belongs_to associations
      const belongsToRegex = /belongs_to\s+:(\w+)/g;
      let match;
      const tableAssocs = {};
      while ((match = belongsToRegex.exec(content)) !== null) {
        const assocName = match[1];
        const targetTable = pluralize(assocName);
        tableAssocs[assocName] = targetTable;
      }

      if (Object.keys(tableAssocs).length > 0) {
        assocMap[tableName] = tableAssocs;
      }
    } catch (err) {
      // Skip files that can't be read
    }
  }
  return assocMap;
}

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
  const hasModelTests = existsSync(modelTestDir) && findRubyTestFiles(modelTestDir).length > 0;
  const hasControllerTests = existsSync(controllerTestDir) && findRubyTestFiles(controllerTestDir).length > 0;
  if (!hasModelTests && !hasControllerTests) return;

  await ensureRuby2jsReady();

  // Parse fixture YAML files
  const fixtures = parseFixtureFiles(appRoot);

  // Build association map from Ruby source files (not transpiled .js)
  const associationMap = buildAssociationMapFromRuby(join(appRoot, 'app/models'));

  // Shared metadata (models aren't transpiled in test-only mode, so this
  // stays empty — but threading it keeps the interface consistent)
  const metadata = { models: {}, concerns: {}, import_mode: 'virtual',
    current_attributes: parseCurrentAttributes(appRoot) };

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
        if (Object.keys(fixtures).length > 0) {
          metadata.fixture_plan = buildFixturePlan(source, fixtures, associationMap);
        } else {
          metadata.fixture_plan = null;
        }
        const result = await transformRuby(source, join(modelTestDir, file), 'test', config, appRoot, metadata);
        let code = result.code;

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
        if (Object.keys(fixtures).length > 0) {
          metadata.fixture_plan = buildFixturePlan(source, fixtures, associationMap);
        } else {
          metadata.fixture_plan = null;
        }
        const result = await transformRuby(source, join(controllerTestDir, file), 'test', config, appRoot, metadata);
        let code = result.code;

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
    only: null        // --only comma-separated list (shorthand for include-only)
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

  // CLI options take precedence
  if (options.database) {
    options.dbName = options.dbName || `${basename(APP_ROOT)}_${env}`.toLowerCase().replace(/[^a-z0-9_]/g, '_');
    return;
  }

  // Load from database.yml
  const configPath = join(APP_ROOT, 'config/database.yml');
  if (existsSync(configPath)) {
    try {
      const content = readFileSync(configPath, 'utf-8');

      if (yaml) {
        // Use js-yaml for proper YAML parsing (handles anchors like <<: *default)
        const config = yaml.load(content);
        const envConfig = config[env];

        if (envConfig) {
          // Rails 7+ multi-database format nests configs under named keys
          // (primary, cache, queue, cable). Use "primary" when present.
          const primaryConfig = (!envConfig.adapter && envConfig.primary) ? envConfig.primary : envConfig;
          if (primaryConfig.adapter) options.database = options.database || primaryConfig.adapter;
          if (primaryConfig.database) options.dbName = options.dbName || primaryConfig.database;
          if (primaryConfig.target) options.target = options.target || primaryConfig.target;
        }
      } else {
        // Fallback: naive parsing (doesn't handle YAML anchors)
        // Used when js-yaml isn't available (standalone CLI from tarball)
        const lines = content.split('\n');
        let currentEnv = null;
        let inEnv = false;

        for (const line of lines) {
          const envMatch = line.match(/^(\w+):$/);
          if (envMatch) {
            currentEnv = envMatch[1];
            inEnv = currentEnv === env;
            continue;
          }

          if (inEnv && line.startsWith('  ')) {
            const adapterMatch = line.match(/^\s+adapter:\s*(.+)$/);
            const databaseMatch = line.match(/^\s+database:\s*(.+)$/);
            const targetMatch = line.match(/^\s+target:\s*(.+)$/);

            if (adapterMatch) options.database = options.database || adapterMatch[1].trim();
            if (databaseMatch) options.dbName = options.dbName || databaseMatch[1].trim();
            if (targetMatch) options.target = options.target || targetMatch[1].trim();
          }
        }
      }
    } catch (e) {
      console.warn(`Warning: Could not parse config/database.yml: ${e.message}`);
    }
  }

  // Normalize adapter names to canonical Juntos equivalents
  // This handles Rails adapter names and common variations
  const ADAPTER_ALIASES = {
    // IndexedDB variations
    indexeddb: 'dexie',
    // SQLite variations (Rails uses sqlite3, npm package is better-sqlite3)
    sqlite3: 'sqlite',
    better_sqlite3: 'sqlite',
    // sql.js variations
    'sql.js': 'sqljs',
    // PostgreSQL variations
    postgres: 'pg',
    postgresql: 'pg',
    // MySQL variations (npm package is mysql2)
    mysql2: 'mysql'
  };
  if (options.database && ADAPTER_ALIASES[options.database]) {
    options.database = ADAPTER_ALIASES[options.database];
  }

  // Environment variables take precedence over defaults (but not over CLI/config)
  options.database = options.database || process.env.JUNTOS_DATABASE || 'dexie';
  options.target = options.target || process.env.JUNTOS_TARGET;
  options.dbName = options.dbName || `${basename(APP_ROOT)}_${env}`.toLowerCase().replace(/[^a-z0-9_]/g, '_');

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

    // Add dependencies if missing (ruby2js and vite-plugin-ruby2js are peer deps of ruby2js-rails)
    if (!existing.dependencies['ruby2js']) {
      existing.dependencies['ruby2js'] = `${RELEASES_URL}/ruby2js-beta.tgz`;
    }
    if (!existing.dependencies['ruby2js-rails']) {
      existing.dependencies['ruby2js-rails'] = `${RELEASES_URL}/ruby2js-rails-beta.tgz`;
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
        'ruby2js-rails': `${RELEASES_URL}/ruby2js-rails-beta.tgz`,
        'vite-plugin-ruby2js': `${RELEASES_URL}/vite-plugin-ruby2js-beta.tgz`
      },
      devDependencies: {
        vite: '^7.0.0',
        vitest: '^2.0.0'
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
import { juntos } from 'ruby2js-rails/vite';

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
    environment: 'node',
    include: ['test/**/*.test.mjs', 'test/**/*.test.js'],
    setupFiles: ['./test/setup.mjs']
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
    writeFileSync(setupPath, `// Test setup for Vitest
// Initializes the database before each test

import { beforeAll, beforeEach } from 'vitest';

beforeAll(async () => {
  // Import models (registers them with Application and modelRegistry)
  await import('juntos:models');

  // Configure migrations
  const rails = await import('juntos:rails');
  const migrations = await import('juntos:migrations');
  rails.Application.configure({ migrations: migrations.migrations });
});

beforeEach(async () => {
  // Fresh in-memory database for each test
  const activeRecord = await import('juntos:active-record');
  await activeRecord.initDatabase({ database: ':memory:' });

  const rails = await import('juntos:rails');
  await rails.Application.runMigrations(activeRecord);
});
`);
  } else {
    if (!quiet) console.log('  Skipping test/setup.mjs (already exists)');
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
# This binstub delegates to the juntos CLI from ruby2js-rails
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
  const result = spawnSync('npm', ['install'], {
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
  node: [],
  bun: [],
  deno: []
};

// Valid target environments for each database adapter
const VALID_TARGETS = {
  // Browser-only databases
  dexie: ['browser', 'capacitor'],
  sqljs: ['browser', 'capacitor', 'electron', 'tauri'],
  pglite: ['browser', 'node', 'capacitor', 'electron', 'tauri'],
  // Node.js databases
  sqlite: ['node', 'bun', 'electron'],
  pg: ['node', 'bun', 'deno', 'electron'],
  mysql: ['node', 'bun', 'electron'],
  // Serverless databases
  neon: ['node', 'vercel', 'vercel-edge', 'capacitor', 'electron', 'tauri'],
  turso: ['node', 'vercel', 'vercel-edge', 'cloudflare', 'capacitor', 'electron', 'tauri'],
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

  // Shared metadata: model/concern filters write here, test filter reads.
  // Survives across convert() calls because Ruby2JS.convert does options.dup
  // (shallow copy), so the mutable metadata object reference persists.
  const metadata = { models: {}, concerns: {}, import_mode: 'eject',
    current_attributes: parseCurrentAttributes(APP_ROOT) };

  // Transform models (including nested subdirectories like account/export.rb)
  const modelsDir = join(APP_ROOT, 'app/models');
  if (existsSync(modelsDir)) {
    const modelFiles = findRubyModelFiles(modelsDir)
      .filter(f => shouldInclude(`app/models/${f}`));

    if (modelFiles.length > 0) {
      console.log('  Transforming models...');
      for (const file of modelFiles) {
        const relativePath = `app/models/${file}`;
        try {
          let source = readFileSync(join(modelsDir, file), 'utf-8');
          // Merge association/scope/callback declarations from included concerns
          // so the Rails model filter generates proper getters and metadata
          if (!file.includes('/')) {
            source = mergeConcernDeclarations(source, modelsDir);
          }
          const result = await transformRuby(source, join(modelsDir, file), null, config, APP_ROOT, metadata);
          // Pass relative output path for correct import resolution
          const relativeOutPath = `app/models/${file.replace('.rb', '.js')}`;
          let code = fixImportsForEject(result.code, relativeOutPath, config);
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

      // Mix concern methods into model prototypes.
      // After transpilation, model subdirectory files (e.g., card/closeable.js)
      // export concern objects with methods. We inject imports and Object.assign
      // calls to apply those methods onto the model class prototype.
      for (const file of modelFiles) {
        if (file.includes('/')) continue; // Skip concern files themselves
        const modelName = file.replace('.rb', '');
        const modelSubdir = join(modelsDir, modelName);
        if (!existsSync(modelSubdir)) continue;

        // Find concern JS files in the model's subdirectory
        const jsFile = join(outDir, 'app/models', modelName + '.js');
        if (!existsSync(jsFile)) continue;

        const concerns = [];
        try {
          for (const entry of readdirSync(join(outDir, 'app/models', modelName), { withFileTypes: true })) {
            if (!entry.isFile() || !entry.name.endsWith('.js')) continue;
            const concernFile = join(outDir, 'app/models', modelName, entry.name);
            const concernContent = readFileSync(concernFile, 'utf-8');
            // Extract concern name from export: `export const Eventable = ...`
            const exportMatch = concernContent.match(/export\s+(?:const|let|var)\s+(\w+)/);
            if (exportMatch) {
              concerns.push({
                name: exportMatch[1],
                path: `./${modelName}/${entry.name}`
              });
            }
          }
        } catch (err) { /* skip */ }

        if (concerns.length > 0) {
          let content = readFileSync(jsFile, 'utf-8');
          // Only mix concerns into classes (which have .prototype),
          // not modules (IIFEs returning plain objects)
          const className = modelName.split('_').map(w => w[0].toUpperCase() + w.slice(1)).join('');
          if (!content.includes(`class ${className}`)) continue;

          // Add concern imports at the top of the file
          const importLines = concerns.map(c =>
            `import { ${c.name} } from '${c.path}';`
          ).join('\n');
          // Defer concern mixing to avoid circular dependency issues with Node ESM.
          // Concerns import their parent model and vice versa. Running the mixing
          // at module scope causes TDZ errors. Instead, register a static _mixConcerns
          // method that setup.mjs calls after all models are loaded.
          const mixBody = concerns.map(c =>
            `    for (const [key, desc] of Object.entries(Object.getOwnPropertyDescriptors(${c.name}))) Object.defineProperty(${className}.prototype, key, desc);`
          ).join('\n');
          const deferredMixin = `${className}._mixConcerns = () => {\n${mixBody}\n};`;
          content = importLines + '\n' + content + '\n' + deferredMixin + '\n';
          writeFileSync(jsFile, content);
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
        base: config.base || '/'
      };
      const pathsResult = convert(source, pathsOptions);
      let pathsCode = pathsResult.toString();
      // For browser targets, use browser path helper
      if (config.target === 'browser') {
        pathsCode = pathsCode.replace(
          /from ['"]ruby2js-rails\/path_helper\.mjs['"]/g,
          "from 'ruby2js-rails/path_helper_browser.mjs'"
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
        base: config.base || '/'
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

    for (const resource of resources) {
      const resourceDir = join(viewsDir, resource);
      const outResourceDir = join(outDir, 'app/views', resource);
      if (!existsSync(outResourceDir)) {
        mkdirSync(outResourceDir, { recursive: true });
      }

      const files = readdirSync(resourceDir);

      // Transform ERB files
      const erbFiles = files
        .filter(f => f.endsWith('.html.erb') && !f.startsWith('._'))
        .filter(f => shouldInclude(`app/views/${resource}/${f}`));

      for (const file of erbFiles) {
        const relativePath = `app/views/${resource}/${file}`;
        try {
          const source = readFileSync(join(resourceDir, file), 'utf-8');
          const result = await transformErb(source, join(resourceDir, file), false, config);
          // Pass relative output path for correct import resolution
          const relativeOutPath = `app/views/${resource}/${file.replace('.html.erb', '.js')}`;
          let code = fixImportsForEject(result.code, relativeOutPath, config);
          const outFile = join(outResourceDir, file.replace('.html.erb', '.js'));
          writeFileSync(outFile, code);
          fileCount++;
        } catch (err) {
          errors.push({ file: relativePath, error: err.message, stack: err.stack });
          console.warn(`    Skipped ${relativePath}: ${formatError(err)}`);
        }
      }

      // Transform JSX.rb files
      const jsxFiles = files
        .filter(f => f.endsWith('.jsx.rb') && !f.startsWith('._'))
        .filter(f => shouldInclude(`app/views/${resource}/${f}`));

      for (const file of jsxFiles) {
        const relativePath = `app/views/${resource}/${file}`;
        try {
          const source = readFileSync(join(resourceDir, file), 'utf-8');
          const result = await transformJsxRb(source, join(resourceDir, file), config);
          // Pass relative output path for correct import resolution
          const relativeOutPath = `app/views/${resource}/${file.replace('.jsx.rb', '.js')}`;
          let code = fixImportsForEject(result.code, relativeOutPath, config);
          const outFile = join(outResourceDir, file.replace('.jsx.rb', '.js'));
          writeFileSync(outFile, code);
          fileCount++;
        } catch (err) {
          errors.push({ file: relativePath, error: err.message, stack: err.stack });
          console.warn(`    Skipped ${relativePath}: ${formatError(err)}`);
        }
      }
    }

    // Generate view index modules for each resource
    for (const resource of resources) {
      const viewsIndex = generateViewsModuleForEject(APP_ROOT, resource);
      writeFileSync(join(outDir, 'app/views', resource + '.js'), viewsIndex);
      fileCount++;
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
    const controllerFiles = readdirSync(appControllersDir)
      .filter(f => f.endsWith('.rb') && !f.startsWith('._'))
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

        // Parse fixture YAML files
        const fixtures = parseFixtureFiles(APP_ROOT);

        // Build association map from transpiled model files
        const associationMap = buildAssociationMap(join(outDir, 'app/models'));

        for (const file of filteredTestFiles) {
          const relativePath = `test/models/${file}`;
          const outName = file.replace(/_test\.rb$/, '.test.mjs');
          try {
            const source = readFileSync(join(modelTestDir, file), 'utf-8');
            if (Object.keys(fixtures).length > 0) {
              metadata.fixture_plan = buildFixturePlan(source, fixtures, associationMap);
            } else {
              metadata.fixture_plan = null;
            }
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

        // Parse fixture YAML files (reuse if already parsed for model tests)
        const ctrlFixtures = parseFixtureFiles(APP_ROOT);
        const ctrlAssociationMap = buildAssociationMap(join(outDir, 'app/models'));

        for (const file of filteredControllerTestFiles) {
          const relativePath = `test/controllers/${file}`;
          const outName = file.replace(/_test\.rb$/, '.test.mjs');
          try {
            const source = readFileSync(join(controllerTestDir, file), 'utf-8');
            if (Object.keys(ctrlFixtures).length > 0) {
              metadata.fixture_plan = buildFixturePlan(source, ctrlFixtures, ctrlAssociationMap);
            } else {
              metadata.fixture_plan = null;
            }
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

  // Generate application_record.js
  console.log('  Generating project files...');
  writeFileSync(join(outDir, 'app/models/application_record.js'), generateApplicationRecordForEject(config));
  fileCount++;

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

  // Generate test/setup.mjs and test/globals.mjs
  const outTestDir = join(outDir, 'test');
  if (!existsSync(outTestDir)) {
    mkdirSync(outTestDir, { recursive: true });
  }
  writeFileSync(join(outTestDir, 'setup.mjs'), generateTestSetupForEject(config));
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

  console.log('\nThe ejected project depends on ruby2js-rails for runtime support.');
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
  server    Start production server (requires prior build)
  deploy    Build and deploy to serverless platform
  up        Build and run locally (node, bun, browser)
  db        Database commands (create, migrate, seed, prepare, drop, reset)
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
