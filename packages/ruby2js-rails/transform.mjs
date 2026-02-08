/**
 * Shared transformation logic for Ruby2JS Rails applications.
 *
 * Used by both vite.mjs (on-the-fly transformation) and cli.mjs (eject command).
 * This ensures ejected output matches what Vite produces.
 */

import path from 'node:path';
import fs from 'node:fs';

// Import ERB compiler for .erb files
import { ErbCompiler } from './lib/erb_compiler.js';

// Import inflector for singularization
import { singularize } from 'ruby2js-rails/adapters/inflector.mjs';

// ============================================================
// Constants
// ============================================================

/**
 * Default target for each database adapter (used when target not specified).
 */
export const DEFAULT_TARGETS = Object.freeze({
  // Browser-only databases
  dexie: 'browser',
  indexeddb: 'browser',
  sqljs: 'browser',
  'sql.js': 'browser',
  pglite: 'browser',

  // TCP-based server databases
  better_sqlite3: 'node',
  sqlite3: 'node',
  sqlite: 'node',
  pg: 'node',
  postgres: 'node',
  postgresql: 'node',
  mysql2: 'node',
  mysql: 'node',

  // Platform-specific databases
  d1: 'cloudflare',
  mpg: 'fly',

  // HTTP-based edge databases
  neon: 'vercel',
  turso: 'vercel',
  libsql: 'vercel',
  planetscale: 'vercel',
  supabase: 'vercel'
});

/**
 * Reserved words that need escaping in exports.
 */
export const RESERVED = new Set([
  'break', 'case', 'catch', 'continue', 'debugger', 'default', 'delete',
  'do', 'else', 'finally', 'for', 'function', 'if', 'in', 'instanceof',
  'new', 'return', 'switch', 'this', 'throw', 'try', 'typeof', 'var',
  'void', 'while', 'with', 'class', 'const', 'enum', 'export', 'extends',
  'import', 'super', 'implements', 'interface', 'let', 'package', 'private',
  'protected', 'public', 'static', 'yield'
]);

// ============================================================
// Helper functions
// ============================================================

/**
 * Capitalize first letter of a string.
 */
export function capitalize(str) {
  return str.charAt(0).toUpperCase() + str.slice(1);
}

// Re-export singularize for convenience
export { singularize };

// ============================================================
// Build options
// ============================================================

/**
 * Get Ruby2JS transpilation options for a given section.
 * Uses filter names as strings (resolved by ruby2js).
 *
 * @param {string} section - The section type ('stimulus', 'controllers', 'jsx', or null for default)
 * @param {string} target - The build target ('browser', 'node', etc.)
 * @param {Object} sectionConfig - Optional section config from ruby2js.yml (e.g., { filters: [...], eslevel: 2022 })
 * @returns {Object} Ruby2JS options
 */
export function getBuildOptions(section, target, sectionConfig = null) {
  const baseOptions = {
    eslevel: sectionConfig?.eslevel || 2022,
    include: sectionConfig?.include || ['class', 'call']
  };

  // Default filter sets for each section
  // Node filter is included for targets with Node.js-compatible APIs (fs, child_process, process.env).
  // See docs/src/_docs/juntos/deploying/index.md for full target list.
  const nodeTargets = ['node', 'bun', 'deno', 'fly', 'electron'];
  const nodeFilter = target && nodeTargets.includes(target) ? ['Node'] : [];
  const defaultFilters = {
    stimulus: ['Pragma', 'Stimulus', 'Functions', 'ESM', 'Return'],
    controllers: ['Pragma', 'Rails_Controller', ...nodeFilter, 'Functions', 'ESM', 'Return'],
    jsx: ['Pragma', 'Rails_Helpers', 'React', 'Functions', 'ESM', 'Return'],
    default: ['Pragma', 'Rails_Concern', 'Rails_Model', 'Rails_Controller', 'Rails_Routes', 'Rails_Seeds', 'Rails_Migration', ...nodeFilter, 'ActiveSupport', 'Functions', 'ESM', 'Return']
  };

  // Use filters from sectionConfig if provided, otherwise use defaults
  // Filter names from config are normalized to match Ruby2JS conventions
  const filters = sectionConfig?.filters
    ? normalizeFilterNames(sectionConfig.filters)
    : defaultFilters[section] || defaultFilters.default;

  switch (section) {
    case 'stimulus':
      return {
        ...baseOptions,
        autoexports: sectionConfig?.autoexports ?? 'default',
        filters,
        target
      };

    case 'controllers':
      return {
        ...baseOptions,
        autoexports: sectionConfig?.autoexports ?? true,
        filters,
        target
      };

    case 'jsx':
      return {
        ...baseOptions,
        autoexports: sectionConfig?.autoexports ?? 'default',
        filters,
        target
      };

    case 'test':
      return {
        ...baseOptions,
        filters: sectionConfig?.filters
          ? normalizeFilterNames(sectionConfig.filters)
          : ['Pragma', 'Rails_Concern', 'Rails_Test', 'Rails_Model', ...nodeFilter, 'ActiveSupport', 'Functions', 'ESM', 'Return'],
        target
      };

    default:
      // Models, routes, seeds, migrations
      return {
        ...baseOptions,
        autoexports: sectionConfig?.autoexports ?? true,
        filters,
        target
      };
  }
}

/**
 * Normalize filter names from ruby2js.yml to Ruby2JS conventions.
 * Converts lowercase names to proper case (e.g., 'stimulus' -> 'Stimulus')
 */
function normalizeFilterNames(filters) {
  const filterMap = {
    // Lowercase to proper case mapping
    'pragma': 'Pragma',
    'stimulus': 'Stimulus',
    'functions': 'Functions',
    'esm': 'ESM',
    'return': 'Return',
    'react': 'React',
    'camelcase': 'CamelCase',
    'rails_controller': 'Rails_Controller',
    'rails_model': 'Rails_Model',
    'rails_routes': 'Rails_Routes',
    'rails_seeds': 'Rails_Seeds',
    'rails_migration': 'Rails_Migration',
    'rails_helpers': 'Rails_Helpers',
    'phlex': 'Phlex',
    'node': 'Node',
    // Also handle slash notation from config
    'rails/controller': 'Rails_Controller',
    'rails/model': 'Rails_Model',
    'rails/routes': 'Rails_Routes',
    'rails/seeds': 'Rails_Seeds',
    'rails/migration': 'Rails_Migration',
    'rails/helpers': 'Rails_Helpers',
    'rails_test': 'Rails_Test',
    'rails/test': 'Rails_Test',
    'activesupport': 'ActiveSupport',
    'active_support': 'ActiveSupport'
  };

  return filters.map(f => filterMap[f.toLowerCase()] || f);
}

// ============================================================
// File discovery
// ============================================================

/**
 * Find all model files in app/models/ (recursive).
 * Returns array of model paths (without .rb extension), e.g. ['account', 'identity/access_token'].
 * Skips concerns/ subdirectory (handled separately via mixins).
 */
export function findModels(appRoot) {
  const modelsDir = path.join(appRoot, 'app/models');
  if (!fs.existsSync(modelsDir)) return [];

  function walk(dir, prefix) {
    const entries = fs.readdirSync(dir, { withFileTypes: true });
    const results = [];
    for (const entry of entries) {
      if (entry.isDirectory()) {
        if (entry.name === 'concerns') continue;
        results.push(...walk(path.join(dir, entry.name), prefix ? `${prefix}/${entry.name}` : entry.name));
      } else if (entry.name.endsWith('.rb') && entry.name !== 'application_record.rb' && !entry.name.startsWith('._')) {
        const name = entry.name.replace('.rb', '');
        results.push(prefix ? `${prefix}/${name}` : name);
      }
    }
    return results;
  }

  return walk(modelsDir, '');
}

/**
 * Derive a JavaScript class name from a model path.
 * 'account' → 'Account', 'identity/access_token' → 'AccessToken'
 * If leafCollisions is provided (Set of leaf names appearing more than once),
 * nested models with colliding leaves get prefixed: 'identity/access_token' → 'IdentityAccessToken'
 */
export function modelClassName(modelPath, leafCollisions) {
  const parts = modelPath.split('/');
  const leaf = parts[parts.length - 1];
  const leafClass = leaf.split('_').map(s => s.charAt(0).toUpperCase() + s.slice(1)).join('');

  if (parts.length === 1 || !leafCollisions || !leafCollisions.has(leafClass)) {
    return leafClass;
  }

  // Collision: prefix with namespace segments
  return parts.map(p => p.split('_').map(s => s.charAt(0).toUpperCase() + s.slice(1)).join('')).join('');
}

/**
 * Find leaf class name collisions among a list of model paths.
 * Returns a Set of leaf class names that appear more than once.
 */
export function findLeafCollisions(models) {
  const counts = {};
  for (const m of models) {
    const parts = m.split('/');
    const leaf = parts[parts.length - 1];
    const leafClass = leaf.split('_').map(s => s.charAt(0).toUpperCase() + s.slice(1)).join('');
    counts[leafClass] = (counts[leafClass] || 0) + 1;
  }
  return new Set(Object.keys(counts).filter(k => counts[k] > 1));
}

/**
 * Find all migration files in db/migrate/.
 * Returns array of { file, name } objects.
 */
export function findMigrations(appRoot) {
  const migrateDir = path.join(appRoot, 'db/migrate');
  if (!fs.existsSync(migrateDir)) return [];
  return fs.readdirSync(migrateDir)
    .filter(f => f.endsWith('.rb') && !f.startsWith('._'))
    .sort()
    .map(f => ({ file: f, name: f.replace('.rb', '') }));
}

/**
 * Find all view resource directories in app/views/.
 * Returns array of directory names (e.g., ['articles', 'comments']).
 */
export function findViewResources(appRoot) {
  const viewsDir = path.join(appRoot, 'app/views');
  if (!fs.existsSync(viewsDir)) return [];
  return fs.readdirSync(viewsDir, { withFileTypes: true })
    .filter(d => d.isDirectory() && d.name !== 'layouts' && !d.name.startsWith('.'))
    .map(d => d.name);
}

/**
 * Find all Stimulus controllers in app/javascript/controllers/.
 * Returns array of { file, name } objects.
 */
export function findControllers(appRoot) {
  const controllersDir = path.join(appRoot, 'app/javascript/controllers');
  if (!fs.existsSync(controllersDir)) return [];
  return fs.readdirSync(controllersDir)
    .filter(f => (f.endsWith('_controller.rb') || f.endsWith('_controller.js')) && !f.startsWith('._'))
    .map(f => ({
      file: f,
      name: f.replace(/_controller\.(rb|js)$/, '').replace(/_/g, '-')
    }));
}

// ============================================================
// Import path rewriting
// ============================================================

/**
 * Fix imports in transpiled code to use virtual modules and source files.
 * Used by Vite plugin for on-the-fly transformation.
 */
export function fixImports(js, fromFile) {
  // Virtual modules for runtime
  js = js.replace(/from ['"]\.\.\/lib\/rails\.js['"]/g, "from 'juntos:rails'");
  js = js.replace(/from ['"]\.\.\/\.\.\/lib\/rails\.js['"]/g, "from 'juntos:rails'");
  js = js.replace(/from ['"]\.\.\/\.\.\/\.\.\/lib\/rails\.js['"]/g, "from 'juntos:rails'");
  js = js.replace(/from ['"]\.\.\/lib\/active_record\.mjs['"]/g, "from 'juntos:active-record'");
  js = js.replace(/from ['"]\.\.\/\.\.\/lib\/active_record\.mjs['"]/g, "from 'juntos:active-record'");

  // ApplicationRecord → virtual module
  js = js.replace(/from ['"]\.\/application_record\.js['"]/g, "from 'juntos:application-record'");

  // Model imports: .js → .rb (same directory, including nested paths like identity/access_token)
  js = js.replace(/from ['"]\.\/([\w/]+)\.js['"]/g, (match, name) => {
    if (name === 'application_record') return "from 'juntos:application-record'";
    return `from './${name}.rb'`;
  });

  // Model imports from controllers: ../models/*.js → ../models/*.rb (including nested paths)
  js = js.replace(/from ['"]\.\.\/models\/([\w/]+)\.js['"]/g, "from '../models/$1.rb'");

  // Views: ../views/*.js → juntos:views/*
  js = js.replace(/from ['"]\.\.\/views\/(\w+)\.js['"]/g, "from 'juntos:views/$1'");
  js = js.replace(/from ['"]\.\.\/views\/(\w+)\/([\w_]+)\.js['"]/g, "from 'app/views/$1/$2.html.erb'");

  // Config: ../../config/paths.js → juntos:paths (path helpers virtual module)
  // This breaks the circular dependency between routes.rb and controllers
  js = js.replace(/from ['"]\.\.\/\.\.\/config\/paths\.js['"]/g, "from 'juntos:paths'");
  js = js.replace(/from ['"]\.\/paths\.js['"]/g, "from 'juntos:paths'");

  // Controllers: ../app/controllers/*.js → app/controllers/*.rb
  js = js.replace(/from ['"]\.\.\/app\/controllers\/(\w+)\.js['"]/g, "from 'app/controllers/$1.rb'");

  // Migrations: ../db/migrate/index.js → juntos:migrations
  js = js.replace(/from ['"]\.\.\/db\/migrate\/index\.js['"]/g, "from 'juntos:migrations'");

  // Seeds: ../db/seeds.js → db/seeds.rb
  js = js.replace(/from ['"]\.\.\/db\/seeds\.js['"]/g, "from 'db/seeds.rb'");

  // Models index: ../app/models/index.js → juntos:models
  js = js.replace(/from ['"]\.\.\/app\/models\/index\.js['"]/g, "from 'juntos:models'");
  js = js.replace(/from ['"]\.\/index\.js['"]/g, (match) => {
    // Only apply if we're in models directory
    if (fromFile.includes('/models/')) return "from 'juntos:models'";
    return match;
  });

  // Layout: ../app/views/layouts/application.js → app/views/layouts/application.html.erb
  js = js.replace(/from ['"]\.\.\/app\/views\/layouts\/application\.js['"]/g,
    "from 'app/views/layouts/application.html.erb'");

  return js;
}

/**
 * Fix imports in test files for ejected code.
 * Rewrites virtual module imports to concrete paths.
 */
export function fixTestImportsForEject(js) {
  // Virtual modules → concrete paths
  js = js.replace(/from ['"]juntos:models['"]/g, "from '../app/models/index.js'");
  js = js.replace(/await import\(['"]juntos:models['"]\)/g, "await import('../app/models/index.js')");

  js = js.replace(/from ['"]juntos:rails['"]/g, "from 'ruby2js-rails/rails_base.js'");
  js = js.replace(/await import\(['"]juntos:rails['"]\)/g, "await import('ruby2js-rails/rails_base.js')");

  js = js.replace(/from ['"]juntos:migrations['"]/g, "from '../db/migrate/index.js'");
  js = js.replace(/await import\(['"]juntos:migrations['"]\)/g, "await import('../db/migrate/index.js')");

  js = js.replace(/from ['"]juntos:active-record['"]/g, "from 'ruby2js-rails/adapters/active_record.mjs'");
  js = js.replace(/await import\(['"]juntos:active-record['"]\)/g, "await import('ruby2js-rails/adapters/active_record.mjs')");

  // Path helpers virtual module → concrete paths.js file
  js = js.replace(/from ['"]juntos:paths['"]/g, "from '../config/paths.js'");
  js = js.replace(/await import\(['"]juntos:paths['"]\)/g, "await import('../config/paths.js')");

  // Controller imports: .rb → .js
  js = js.replace(/from ['"]\.\.\/app\/controllers\/(\w+)\.rb['"]/g, "from '../app/controllers/$1.js'");
  js = js.replace(/await import\(['"]\.\.\/app\/controllers\/(\w+)\.rb['"]\)/g, "await import('../app/controllers/$1.js')");

  return js;
}

/**
 * Fix imports for ejected code - rewrites to use ruby2js-rails package.
 * Ejected code depends on the juntos runtime, not copied local files.
 * @param {string} js - The JavaScript code to fix
 * @param {string} fromFile - Relative output path of the file (e.g., 'app/models/article.js')
 * @param {object} config - Configuration with target/database info
 */
export function fixImportsForEject(js, fromFile, config = {}) {
  // Determine the target runtime based on config
  // Default to 'node' for sqlite3/better_sqlite3, 'browser' for dexie
  let target = config.target || 'node';
  if (!config.target && config.database === 'dexie') {
    target = 'browser';
  }

  const railsModule = `ruby2js-rails/targets/${target}/rails.js`;

  // Runtime modules → target-specific rails.js
  js = js.replace(/from ['"]\.\.\/lib\/rails\.js['"]/g, `from '${railsModule}'`);
  js = js.replace(/from ['"]\.\.\/\.\.\/lib\/rails\.js['"]/g, `from '${railsModule}'`);
  js = js.replace(/from ['"]\.\.\/\.\.\/\.\.\/lib\/rails\.js['"]/g, `from '${railsModule}'`);
  js = js.replace(/from ['"]lib\/rails\.js['"]/g, `from '${railsModule}'`);
  js = js.replace(/from ['"]ruby2js-rails\/rails_base\.js['"]/g, `from '${railsModule}'`);
  js = js.replace(/from ['"]\.\.\/lib\/active_record\.mjs['"]/g, "from 'ruby2js-rails/adapters/active_record.mjs'");
  js = js.replace(/from ['"]\.\.\/\.\.\/lib\/active_record\.mjs['"]/g, "from 'ruby2js-rails/adapters/active_record.mjs'");

  // ActiveStorage virtual module → adapter
  js = js.replace(/from ['"]juntos:active-storage['"]/g, "from 'ruby2js-rails/adapters/active_storage_base.mjs'");

  // URL helpers virtual module → url_helpers
  js = js.replace(/from ['"]juntos:url-helpers['"]/g, "from 'ruby2js-rails/url_helpers.mjs'");

  // Virtual module @config/paths.js → config/paths.js with correct relative path
  // Path helpers are in a separate file to avoid circular dependency with routes.js
  if (fromFile) {
    // Calculate relative path from the file to config/paths.js
    const depth = fromFile.split('/').length - 1;
    const prefix = '../'.repeat(depth);
    js = js.replace(/from ['"]@config\/paths\.js['"]/g, `from '${prefix}config/paths.js'`);
  } else {
    // Fallback: assume we're one level deep
    js = js.replace(/from ['"]@config\/paths\.js['"]/g, "from '../config/paths.js'");
  }

  // Fix selfhost converter Struct.new pattern: [(X = function X(...) {...}).prototype] = [X.prototype]
  // The right side references X before assignment completes. Simplify to plain let declaration.
  // ESM strict mode requires variable declaration (no implicit globals).
  js = js.replace(/^\[\((\w+ = function \w+\([^)]*\) \{[\s\S]*?\})\)\.prototype\] = \[\w+\.prototype\];?/m,
    'let $1;');

  // Fix alias_method pattern: X.prototype.alias = X.prototype.original
  // This fails at load time when original is a getter accessing private fields.
  // Use a helper that walks the prototype chain to find the descriptor.
  js = js.replace(
    /^(\w+)\.prototype\.(\w+) = \1\.prototype\.(\w+)$/gm,
    '{ let _p = $1.prototype; while (_p && !Object.getOwnPropertyDescriptor(_p, "$3")) _p = Object.getPrototypeOf(_p); if (_p) Object.defineProperty($1.prototype, "$2", Object.getOwnPropertyDescriptor(_p, "$3")); }');

  // Handle relative paths to config/paths.js (keep as paths.js, not routes.js)
  // This is used for controllers: ../../config/paths.js → ../../config/paths.js
  // No change needed - paths.js is the correct target

  // For nested model files (in subdirectories), adjust ./ imports to point back to models root.
  // The model filter generates all paths relative to app/models/, but nested files are in subdirs.
  // e.g., identity/access_token.js has './application_record.js' → '../application_record.js'
  if (fromFile && fromFile.startsWith('app/models/')) {
    const modelRelPath = fromFile.replace('app/models/', '');
    const depth = modelRelPath.split('/').length - 1; // 0 for top-level, 1 for identity/x.js, etc.
    if (depth > 0) {
      const prefix = '../'.repeat(depth);
      js = js.replace(/from ['"]\.\/([\w/]+\.js)['"]/g, `from '${prefix}$1'`);
    }
  }

  // Add missing superclass imports for nested model files.
  // When ESM autoexport unnests a namespaced class (e.g., Account::Export < Export),
  // the model filter may not generate an import for the superclass if it doesn't recognize
  // the class as an ActiveRecord model. We detect `extends ClassName` without a matching
  // import and add it, using the models list to find the correct path.
  if (fromFile && fromFile.startsWith('app/models/') && config.models) {
    const modelRelPath = fromFile.replace('app/models/', '').replace(/\.js$/, '');
    const depth = modelRelPath.split('/').length - 1;
    if (depth > 0) {
      // Check for extends clause without a corresponding import
      const extendsMatch = js.match(/(?:class \w+ extends |class extends )(\w+)\s*\{/);
      if (extendsMatch) {
        const superclassName = extendsMatch[1];
        // Check if this superclass is already imported
        const importPattern = new RegExp(`import\\s+\\{[^}]*\\b${superclassName}\\b[^}]*\\}\\s+from`);
        if (!importPattern.test(js) && superclassName !== 'ApplicationRecord') {
          // Convert PascalCase to snake_case to find the model file
          const snakeName = superclassName.replace(/([A-Z])/g, '_$1').toLowerCase().replace(/^_/, '');
          // Try same-namespace path first (e.g., account/data_transfer/record_set for RecordSet
          // in account/data_transfer/account_record_set.js), then top-level.
          // Skip self-references (account/export shouldn't import from itself).
          const currentNamespace = modelRelPath.split('/').slice(0, -1).join('/');
          const namespacedPath = currentNamespace ? `${currentNamespace}/${snakeName}` : snakeName;
          if (namespacedPath !== modelRelPath && config.models.includes(namespacedPath)) {
            const prefix = '../'.repeat(depth);
            js = `import { ${superclassName} } from '${prefix}${namespacedPath}.js';\n${js}`;
          } else if (config.models.includes(snakeName)) {
            const prefix = '../'.repeat(depth);
            js = `import { ${superclassName} } from '${prefix}${snakeName}.js';\n${js}`;
          }
        }
      }
    }
  }

  // Handle dotted superclass references from Ruby's :: namespace operator.
  // Ruby's Account::DataTransfer::RecordSet becomes Account.DataTransfer.RecordSet in JS,
  // but that's a property chain requiring Account to exist. Instead, resolve the full
  // namespace path to a direct import of the leaf class.
  // e.g., extends Account.DataTransfer.RecordSet → import { RecordSet } from './record_set.js'
  if (fromFile && fromFile.startsWith('app/models/') && config.models) {
    const dottedMatch = js.match(/class \w+ extends ((\w+\.)+\w+)\s*\{/);
    if (dottedMatch) {
      const dottedName = dottedMatch[1]; // e.g., "Account.DataTransfer.RecordSet"
      const parts = dottedName.split('.'); // ['Account', 'DataTransfer', 'RecordSet']
      const leafName = parts[parts.length - 1]; // 'RecordSet'

      // Convert PascalCase parts to snake_case path
      const pathParts = parts.map(p => p.replace(/([A-Z])/g, '_$1').toLowerCase().replace(/^_/, ''));
      const superModelPath = pathParts.join('/'); // 'account/data_transfer/record_set'

      if (config.models.includes(superModelPath)) {
        // Compute relative path from current file to superclass file
        const modelRelPath = fromFile.replace('app/models/', '').replace(/\.js$/, '');
        const currentDir = modelRelPath.split('/').slice(0, -1);
        const superDir = pathParts.slice(0, -1);
        const superFile = pathParts[pathParts.length - 1];

        // Find common directory prefix
        let common = 0;
        while (common < currentDir.length && common < superDir.length &&
               currentDir[common] === superDir[common]) {
          common++;
        }

        // Build relative path
        const up = currentDir.length - common;
        const down = superDir.slice(common);
        let relativePath;
        if (up === 0 && down.length === 0) {
          relativePath = `./${superFile}.js`;
        } else if (up === 0) {
          relativePath = `./${[...down, superFile + '.js'].join('/')}`;
        } else {
          relativePath = [...Array(up).fill('..'), ...down, superFile + '.js'].join('/');
        }

        // Replace dotted extends with leaf name and add import
        js = js.replace(`extends ${dottedName}`, `extends ${leafName}`);
        js = `import { ${leafName} } from '${relativePath}';\n${js}`;
      }
    }
  }

  // Add missing imports for included concerns (Object.getOwnPropertyDescriptors references).
  // The class2 converter translates `include Foo` to Object.defineProperties(..., Object.getOwnPropertyDescriptors(Foo))
  // but doesn't generate the import for Foo. We detect unimported references and add them.
  if (fromFile && fromFile.startsWith('app/models/') && config.models) {
    const modelRelPath = fromFile.replace('app/models/', '').replace(/\.js$/, '');
    const depth = modelRelPath.split('/').length - 1;
    const descriptorRefs = [...js.matchAll(/Object\.getOwnPropertyDescriptors\((\w+)\)/g)];
    for (const match of descriptorRefs) {
      const refName = match[1];
      const importPattern = new RegExp(`import\\s+\\{[^}]*\\b${refName}\\b[^}]*\\}\\s+from`);
      if (!importPattern.test(js)) {
        // Convert PascalCase to snake_case to find the model/concern file
        const snakeName = refName.replace(/([A-Z])/g, '_$1').toLowerCase().replace(/^_/, '');
        // Try namespace-prefixed path first (e.g., webhook/triggerable for Triggerable in webhook.js)
        const nested = `${modelRelPath}/${snakeName}`;
        const prefix = '../'.repeat(depth);
        if (config.models.includes(nested)) {
          js = `import { ${refName} } from '${prefix || './'}${nested}.js';\n${js}`;
        } else if (config.models.includes(snakeName)) {
          js = `import { ${refName} } from '${prefix || './'}${snakeName}.js';\n${js}`;
        }
      }
    }
  }

  // General model reference imports: scan for bare ClassName.method or new ClassName(
  // references to known model classes that aren't imported. This handles cases like
  // concern modules referencing Color.COLORS or Color.for_value() without an import.
  if (fromFile && fromFile.startsWith('app/models/') && config.models && config.modelClassMap) {
    const modelRelPath = fromFile.replace('app/models/', '').replace(/\.js$/, '');
    const depth = modelRelPath.split('/').length - 1;

    for (const [className, modelPath] of Object.entries(config.modelClassMap)) {
      // Skip if already imported
      const importPattern = new RegExp(`import\\s+\\{[^}]*\\b${className}\\b[^}]*\\}\\s+from`);
      if (importPattern.test(js)) continue;

      // Skip self-references
      if (modelPath === modelRelPath) continue;

      // Skip if this file defines/exports a class with the same name (name collision between namespaces)
      // e.g., card/entropy.js exports class Entropy — don't import Entropy from ../entropy.js
      const definesClass = new RegExp(`(export\\s+)?(class|const|let|var|function)\\s+${className}\\b`);
      if (definesClass.test(js)) continue;

      // Skip references to models in a subdirectory named after this file.
      // e.g., notifier.js should not import from notifier/mention_notifier.js
      // because those subclasses typically extend the parent, creating a circular dependency.
      const baseName = modelRelPath.split('/').pop();
      if (modelPath.startsWith(modelRelPath.replace(/[^/]+$/, baseName + '/'))) continue;

      // Check if this class name is referenced (ClassName.something or new ClassName)
      const refPattern = new RegExp(`\\b${className}\\b\\.\\w|\\bnew\\s+${className}\\b`);
      if (!refPattern.test(js)) continue;

      // Compute relative path
      const currentDir = modelRelPath.split('/').slice(0, -1);
      const targetParts = modelPath.split('/');
      const targetDir = targetParts.slice(0, -1);
      const targetFile = targetParts[targetParts.length - 1];

      let common = 0;
      while (common < currentDir.length && common < targetDir.length &&
             currentDir[common] === targetDir[common]) {
        common++;
      }
      const up = currentDir.length - common;
      const down = targetDir.slice(common);
      let relativePath;
      if (up === 0 && down.length === 0) {
        relativePath = `./${targetFile}.js`;
      } else if (up === 0) {
        relativePath = `./${[...down, targetFile + '.js'].join('/')}`;
      } else {
        relativePath = [...Array(up).fill('..'), ...down, targetFile + '.js'].join('/');
      }

      js = `import { ${className} } from '${relativePath}';\n${js}`;
    }
  }

  // Model imports: resolve nested model paths using actual models list.
  // For top-level model files, resolve association imports to nested paths when needed.
  // e.g., in identity.js: import { AccessToken } from './access_token.js'
  //   → import { AccessToken } from './identity/access_token.js'
  // This handles Rails' namespace convention where Identity has_many :access_tokens
  // maps to Identity::AccessToken at app/models/identity/access_token.rb
  if (fromFile && fromFile.startsWith('app/models/') && config.models) {
    const modelRelPath = fromFile.replace('app/models/', '').replace(/\.js$/, '');
    const depth = modelRelPath.split('/').length - 1;
    if (depth === 0) {
      // Top-level model: resolve flat imports to nested paths when the model doesn't exist at top level
      const topLevelModels = new Set(config.models.filter(m => !m.includes('/')));
      js = js.replace(/from ['"]\.\/([\w]+)\.js['"]/g, (match, name) => {
        if (name === 'application_record') return match;
        if (topLevelModels.has(name)) return match;
        // Try namespace-prefixed path (e.g., identity/access_token)
        const nested = `${modelRelPath}/${name}`;
        if (config.models.includes(nested)) {
          return `from './${nested}.js'`;
        }
        return match;
      });
    }
  }
  // Controller concerns: redirect from ../models/board_scoped.js to ./concerns/board_scoped.js
  // The controller filter generates proper snake_case names (BoardScoped -> board_scoped)
  const concernPatterns = ['scoped', 'authentication', 'authorization'];
  js = js.replace(/from ['"]\.\.\/models\/([\w/]+)\.js['"]/g, (match, name) => {
    // Nested paths (containing /) are real model imports, not concerns
    if (name.includes('/')) return match;
    const isLikelyConcern = concernPatterns.some(pattern => name.toLowerCase().includes(pattern));
    if (isLikelyConcern) {
      return `from './concerns/${name}.js'`;
    }
    return match;
  });

  // Path helper → ruby2js-rails package
  js = js.replace(/from ['"]ruby2js-rails\/path_helper\.mjs['"]/g, "from 'ruby2js-rails/path_helper.mjs'");

  return js;
}

// ============================================================
// Virtual module content generators
// ============================================================

/**
 * Generate content for juntos:models virtual module.
 */
export function generateModelsModule(appRoot) {
  const models = findModels(appRoot);
  const collisions = findLeafCollisions(models);
  const imports = models.map(m => {
    const leafClass = m.split('/').pop().split('_').map(s => s.charAt(0).toUpperCase() + s.slice(1)).join('');
    const alias = modelClassName(m, collisions);
    if (alias !== leafClass) {
      return `import { ${leafClass} as ${alias} } from 'app/models/${m}.rb';`;
    }
    return `import { ${alias} } from 'app/models/${m}.rb';`;
  });
  const classNames = models.map(m => modelClassName(m, collisions));
  return `${imports.join('\n')}
import { Application } from 'juntos:rails';
import { modelRegistry } from 'juntos:active-record';
const models = { ${classNames.join(', ')} };
Application.registerModels(models);
Object.assign(modelRegistry, models);
export { ${classNames.join(', ')} };
`;
}

/**
 * Generate content for juntos:models for ejected output.
 * Uses ruby2js-rails package for runtime, local paths for app code.
 */
export function generateModelsModuleForEject(appRoot, config = {}) {
  let models = findModels(appRoot);
  // Exclude models that failed to transpile (e.g., unsupported syntax like class << self)
  if (config.excludeModels) {
    models = models.filter(m => !config.excludeModels.has(m));
  }
  const collisions = findLeafCollisions(models);
  const adapterFile = getActiveRecordAdapterFile(config.database);

  // Determine target for importing Application
  let target = config.target || 'node';
  if (!config.target && config.database === 'dexie') {
    target = 'browser';
  }
  const railsModule = `ruby2js-rails/targets/${target}/rails.js`;

  // Read actual exported class names from transpiled files when outDir is available.
  // This handles cases like IO (Ruby) vs Io (PascalCase from filename).
  function getActualExportName(modelPath) {
    if (config.outDir) {
      try {
        const jsPath = path.join(config.outDir, 'app/models', modelPath + '.js');
        const content = fs.readFileSync(jsPath, 'utf-8');
        // Look for export class X, export const X, or export { X } or export { Y as X }
        const classMatch = content.match(/export\s+(?:class|const|function)\s+(\w+)/);
        if (classMatch) return classMatch[1];
        const aliasMatch = content.match(/export\s*\{\s*\w+\s+as\s+(\w+)\s*\}/);
        if (aliasMatch) return aliasMatch[1];
        const namedMatch = content.match(/export\s*\{\s*(\w+)\s*\}/);
        if (namedMatch) return namedMatch[1];
      } catch {}
    }
    return null;
  }

  const imports = models.map(m => {
    const actualName = getActualExportName(m);
    const alias = modelClassName(m, collisions);
    const importName = actualName || m.split('/').pop().split('_').map(s => s.charAt(0).toUpperCase() + s.slice(1)).join('');
    if (alias !== importName) {
      return `import { ${importName} as ${alias} } from './${m}.js';`;
    }
    return `import { ${alias} } from './${m}.js';`;
  });
  const classNames = models.map(m => modelClassName(m, collisions));

  // Build nesting map: models in subdirectories nest under parent model
  // e.g., search/highlighter -> Search.Highlighter
  const nestingPairs = [];
  for (const m of models) {
    const parts = m.split('/');
    if (parts.length >= 2) {
      const parentPath = parts.slice(0, -1).join('/');
      const parentName = modelClassName(parentPath, collisions);
      const childName = modelClassName(m, collisions);
      // Only nest if parent model exists
      if (models.includes(parentPath)) {
        nestingPairs.push(`["${parentName}", "${childName}"]`);
      }
    }
  }
  const nestingCode = nestingPairs.length > 0
    ? `\n// Model nesting for Ruby namespace resolution (e.g., Search::Highlighter -> Search.Highlighter)\nglobalThis._modelNesting = [${nestingPairs.join(', ')}];\n`
    : '';

  return `${imports.join('\n')}
import { Application } from '${railsModule}';
import { modelRegistry, attr_accessor } from 'ruby2js-rails/adapters/${adapterFile}';
import { migrations } from '../../db/migrate/index.js';
const models = { ${classNames.join(', ')} };
Application.registerModels(models);
Object.assign(modelRegistry, models);

// Define attribute accessors from migration schema (like Rails schema.rb)
for (const migration of migrations) {
  if (!migration.tableSchemas) continue;
  for (const [table, schema] of Object.entries(migration.tableSchemas)) {
    const model = Object.values(models).find(m => m.tableName === table);
    if (!model) continue;
    const columns = schema.split(', ').map(c => c.replace(/^[+&]*/g, '')).filter(c => c !== 'id');
    attr_accessor(model, ...columns);
  }
}
${nestingCode}
export { ${classNames.join(', ')} };
`;
}

/**
 * Generate application_record.js for ejected output.
 * This provides the base class for all models.
 */
export function generateApplicationRecordForEject(config = {}) {
  const adapterFile = getActiveRecordAdapterFile(config.database);
  return `import { ActiveRecord as Base, CollectionProxy, modelRegistry } from 'ruby2js-rails/adapters/${adapterFile}';
import { Reference, HasOneReference } from 'ruby2js-rails/adapters/reference.mjs';

export class ApplicationRecord extends Base {
  static primaryAbstractClass = true;
}

export { CollectionProxy, modelRegistry, Reference, HasOneReference };
`;
}

/**
 * Generate package.json for ejected output.
 */
export function generatePackageJsonForEject(appName, config = {}) {
  const RELEASES_BASE = 'https://ruby2js.github.io/ruby2js/releases';

  // Determine if this is a browser target
  const browserTargets = ['browser', 'pwa', 'capacitor', 'electron', 'tauri'];
  const isBrowserTarget = browserTargets.includes(config.target);

  const scripts = {
    dev: 'vite',
    build: 'vite build',
    preview: 'vite preview',
    test: 'vitest run'
  };

  // Only add start script for server targets
  if (!isBrowserTarget) {
    scripts.start = 'node main.js';
  }

  const pkg = {
    name: appName,
    type: 'module',
    scripts,
    dependencies: {
      'ruby2js': `${RELEASES_BASE}/ruby2js-beta.tgz`,
      'ruby2js-rails': `${RELEASES_BASE}/ruby2js-rails-beta.tgz`,
      'react': '^18.0.0',
      'react-dom': '^18.0.0'
    },
    devDependencies: {
      'vite': '^7.0.0',
      'vitest': '^2.0.0'
    }
  };

  // Add browser dependencies
  if (isBrowserTarget) {
    pkg.dependencies['@hotwired/turbo'] = '^8.0.0';
    pkg.dependencies['@hotwired/stimulus'] = '^3.2.0';
  }

  // Add database adapter dependency based on config
  // sqlite/sqlite3 use built-in node:sqlite (no dependency needed)
  if (config.database === 'better_sqlite3') {
    pkg.dependencies['better-sqlite3'] = '^11.10.0';
  } else if (config.database === 'dexie') {
    pkg.dependencies['dexie'] = '^4.0.0';
  }

  return JSON.stringify(pkg, null, 2) + '\n';
}

/**
 * Generate test/setup.mjs for ejected output.
 */
export function generateTestSetupForEject(config = {}) {
  const adapterFile = getActiveRecordAdapterFile(config.database);

  // Determine target for importing Application
  let target = config.target || 'node';
  if (!config.target && config.database === 'dexie') {
    target = 'browser';
  }
  const railsModule = `ruby2js-rails/targets/${target}/rails.js`;

  return `// Test setup for Vitest - ejected version
import { beforeAll, beforeEach } from 'vitest';

beforeAll(async () => {
  // Import models (registers them with Application and modelRegistry)
  const models = await import('../app/models/index.js');

  // Make all models globally available (Rails autoloads all models)
  // Also detect nested model patterns (e.g. ZipFile + Writer -> ZipFile.Writer)
  const modelNames = Object.keys(models);
  for (const [name, value] of Object.entries(models)) {
    if (typeof value === 'function' || typeof value === 'object') {
      globalThis[name] = value;
    }
  }
  // Attach nested classes to parent namespaces and mix in concern methods
  // e.g., Card.Closeable = Closeable, then mix Closeable methods into Card.prototype
  const _nesting = (globalThis._modelNesting || []);
  for (const [parent, child] of _nesting) {
    if (globalThis[parent] && globalThis[child]) {
      globalThis[parent][child] = globalThis[child];

      // If child is a plain object (concern module), mix its methods into parent prototype
      const childVal = globalThis[child];
      if (typeof childVal === 'object' && childVal !== null && typeof globalThis[parent] === 'function') {
        Object.defineProperties(
          globalThis[parent].prototype,
          Object.getOwnPropertyDescriptors(childVal)
        );
      }
    }
  }
  // Promote CurrentAttributes instance methods to static on Current
  if (globalThis.Current?._promoteInstanceMethods) Current._promoteInstanceMethods();

  // Configure migrations
  const { Application } = await import('${railsModule}');
  const { migrations } = await import('../db/migrate/index.js');
  Application.configure({ migrations });
});

beforeEach(async () => {
  // Fresh in-memory database for each test
  const activeRecord = await import('ruby2js-rails/adapters/${adapterFile}');
  await activeRecord.initDatabase({ database: ':memory:' });

  const { Application } = await import('${railsModule}');
  await Application.runMigrations(activeRecord);
});
`;
}

/**
 * Generate test/globals.mjs with Ruby pattern stubs.
 * Separate from setup.mjs so it can be imported without vitest context.
 */
export function generateTestGlobalsForEject() {
  return `// Global stubs for Ruby patterns that don't have direct JS equivalents
// These are defined here so tests can load without errors

// $private() - Ruby's private method marker, no-op in JS (functions are already scoped)
globalThis.$private = function() {};

// include() - Ruby module inclusion, stubbed for now
// TODO: Implement proper module mixin support
globalThis.include = function(module) {
  // No-op for now - tests that need shared setup will fail until helpers are implemented
};

// extend() - Ruby module extension (extend self makes module methods callable on the module itself)
globalThis.extend = function(target) {
  // No-op - in IIFE module pattern, methods are already accessible
};

// ActiveSupport stub for patterns like ActiveSupport::Concern and CurrentAttributes
globalThis.ActiveSupport = {
  Concern: {},
  CurrentAttributes: class CurrentAttributes {
    static _attributes = {};
    static attribute(...names) {
      for (const name of names) {
        if (!(name in this)) {
          Object.defineProperty(this, name, {
            get() { return this._attributes[name]; },
            set(v) { this._attributes[name] = v; },
            configurable: true
          });
        }
      }
    }
    static reset() { this._attributes = {}; }
    static $with(attrs, fn) {
      const prev = { ...this._attributes };
      Object.assign(this._attributes, attrs);
      try { return fn?.(); } finally { this._attributes = prev; }
    }
    // Promote instance methods to static on subclasses
    static _promoteInstanceMethods() {
      const proto = this.prototype;
      for (const name of Object.getOwnPropertyNames(proto)) {
        if (name === 'constructor') continue;
        const desc = Object.getOwnPropertyDescriptor(proto, name);
        if (desc && typeof desc.value === 'function' && !(name in this)) {
          this[name] = desc.value.bind(this);
        }
      }
    }
  }
};

// validates/validate - ActiveModel class-level validation DSL
// In Rails these come from ActiveModel::Validations::ClassMethods via include
// The transpiled code calls them as static methods (e.g., Signup.validates(...))
Function.prototype.validates = Function.prototype.validates || function() {};
Function.prototype.validate = Function.prototype.validate || function() {};

// delegate() - Rails delegation DSL, no-op stub
// In Rails: Model.delegate(:method, to: :association)
// Make available on all classes
Function.prototype.delegate = Function.prototype.delegate || function() {};

// Rails namespace stub
globalThis.Rails = { application: { config: {} } };

// ActionMailer stub for ActionMailer.TestHelper
globalThis.ActionMailer = {
  TestHelper: { name: 'ActionMailer.TestHelper' }
};

// PlatformAgent stub (from platform_agent gem - not available in JS)
globalThis.PlatformAgent = class PlatformAgent {
  constructor(userAgent) { this._userAgent = userAgent || ''; }
  get user_agent() { return { browser: this._userAgent, platform: this._userAgent }; }
  match(pattern) { return pattern.test(this._userAgent); }
};

// URI namespace — Ruby stdlib, used for URI::MailTo::EMAIL_REGEXP etc.
globalThis.URI = {
  MailTo: {
    EMAIL_REGEXP: /\\A[a-zA-Z0-9.!#$%&'*+\\/=?^_\`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*\\z/
  },
  parse(str) { try { return new URL(str); } catch { return null; } },
  encode_www_form_component(s) { return encodeURIComponent(String(s)); }
};

// --- Framework namespace stubs ---
// These allow models to load without crashing. The stubs provide the right
// shape (classes, static methods, exception types) but not real behavior.

// Helper: stub class with common ActiveRecord-style static methods
function _stubModelClass(name) {
  return class StubModel {
    static _name = name;
    constructor(attrs) { Object.assign(this, attrs || {}); }
    static where() { return []; }
    static find_by() { return null; }
    static exists() { return false; }
    static create() { return new this(); }
    static create_and_upload() { return new this(); }
    static insert_all() {}
    static column_names = [];
    update(attrs) { Object.assign(this, attrs); return this; }
  };
}

// ERB namespace — ERB.Util is mixed in via Object.getOwnPropertyDescriptors
globalThis.ERB = {
  Util: {
    html_escape(s) { return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); },
    url_encode(s) { return encodeURIComponent(String(s)); }
  }
};

// ActiveStorage namespace
globalThis.ActiveStorage = {
  Blob: Object.assign(_stubModelClass('ActiveStorage::Blob'), {
    service: { name: 'local' },
    services: { fetch(name) { return { name }; } }
  }),
  Attachment: _stubModelClass('ActiveStorage::Attachment'),
  FileNotFoundError: class FileNotFoundError extends Error { name = 'ActiveStorage::FileNotFoundError' },
  PurgeJob: class PurgeJob {},
  Service: {
    S3Service: class S3Service {}
  }
};

// ActionText namespace
globalThis.ActionText = {
  RichText: _stubModelClass('ActionText::RichText'),
  Attachment: Object.assign(_stubModelClass('ActionText::Attachment'), {
    from_attachable(blob) { return { to_html: '<div></div>' }; }
  }),
  Content: class Content {
    constructor(html) { this._html = html || ''; }
    append_attachables() { return this; }
    toString() { return this._html; }
  },
  Attachables: {
    RemoteImage: class RemoteImage {}
  }
};

// ActiveRecord namespace additions (extends existing ActiveRecord from adapter)
if (!globalThis.ActiveRecord) globalThis.ActiveRecord = {};
Object.assign(globalThis.ActiveRecord, {
  FixtureSet: {
    identify(name, count) {
      // Simple hash for deterministic fixture IDs (matches Rails behavior loosely)
      let hash = 0;
      for (let i = 0; i < name.length; i++) hash = ((hash << 5) - hash + name.charCodeAt(i)) | 0;
      return Math.abs(hash);
    }
  },
  Type: {
    Boolean: class BooleanType {
      cast(val) {
        if (val === 'true' || val === '1' || val === 1 || val === true) return true;
        if (val === 'false' || val === '0' || val === 0 || val === false || val == null) return false;
        return !!val;
      }
    },
    Uuid: Object.assign(
      class UuidType {
        serialize(val) { return String(val); }
      },
      { generate: crypto.randomUUID ? crypto.randomUUID.bind(crypto) : () => Math.random().toString(36).slice(2) }
    ),
    lookup(name) {
      if (name === 'boolean') return new this.Boolean();
      if (name === 'uuid') return new this.Uuid();
      return { cast(v) { return v; }, serialize(v) { return v; } };
    }
  },
  RecordNotFound: class RecordNotFound extends Error { name = 'ActiveRecord::RecordNotFound' },
  RecordInvalid: class RecordInvalid extends Error { name = 'ActiveRecord::RecordInvalid' },
  RecordNotUnique: class RecordNotUnique extends Error { name = 'ActiveRecord::RecordNotUnique' },
  RecordNotSaved: class RecordNotSaved extends Error { name = 'ActiveRecord::RecordNotSaved' },
  ValueTooLong: class ValueTooLong extends Error { name = 'ActiveRecord::ValueTooLong' },
  CheckViolation: class CheckViolation extends Error { name = 'ActiveRecord::CheckViolation' },
  Base: {
    connection_pool: {
      with_connection(fn) { return fn(); }
    }
  }
});

// ActiveModel namespace — mixed in via Object.getOwnPropertyDescriptors
globalThis.ActiveModel = {
  Model: {},
  Attributes: {
    attribute() {}
  },
  Validations: {
    validates() {},
    validate() {}
  }
};

// ZipKit namespace — RemoteIO is used as a superclass (extends ZipKit.RemoteIO)
globalThis.ZipKit = {
  RemoteIO: class RemoteIO {
    constructor(uri) { this._uri = uri; }
  },
  FileReader: Object.assign(
    class FileReader {},
    {
      read_zip_structure(opts) { return []; },
      InvalidStructure: class InvalidStructure extends Error { name = 'ZipKit::FileReader::InvalidStructure' }
    }
  ),
  Streamer: class Streamer {
    constructor(io) { this._io = io; }
    write_deflated_file() {}
    write_stored_file() {}
    close() {}
  }
};

// Mittens stub — snowball stemmer gem (mittens-ruby), used for search
globalThis.Mittens = {
  Stemmer: class Stemmer {
    stem(word) { return String(word || '').toLowerCase(); }
  }
};

// IPAddr stub — Ruby stdlib class for IP address parsing/matching
globalThis.IPAddr = class IPAddr {
  constructor(str) { this._str = str; }
  include(addr) { return false; }
  to_s() { return this._str; }
};

// App helper stubs — Rails helpers mixed into models via include/Object.getOwnPropertyDescriptors.
// These are app-specific but referenced at model load time, so we stub them here.
globalThis.ExcerptHelper = {
  format_excerpt(content, opts) { return String(content || '').slice(0, (opts?.length || 200)); }
};
globalThis.TimeHelper = {
  local_datetime_tag(datetime, opts) { return ''; }
};

// ActionView namespace — helpers mixed in via Object.getOwnPropertyDescriptors
globalThis.ActionView = {
  Helpers: {
    TagHelper: {
      tag: Object.assign(function tag(name, opts) { return ''; }, {
        div(content, opts) { return '<div>' + (content || '') + '</div>'; },
        span(content, opts) { return '<span>' + (content || '') + '</span>'; },
        p(content, opts) { return '<p>' + (content || '') + '</p>'; }
      }),
      content_tag(name, content, opts) { return '<' + name + '>' + (content || '') + '</' + name + '>'; }
    },
    OutputSafetyHelper: {
      safe_join(arr, sep) { return arr.join(sep || ''); },
      raw(s) { return String(s); }
    }
  },
  RecordIdentifier: {
    dom_id(record, prefix) {
      const name = (record?.constructor?.name || 'record').replace(/([a-z])([A-Z])/g, '$1_$2').toLowerCase();
      const id = record?.id || 'new';
      return prefix ? prefix + '_' + name + '_' + id : name + '_' + id;
    }
  }
};

// --- Rails test helper stubs ---

// assert_difference(expression, difference, fn) - verify a numeric change
globalThis.assert_difference = async function(expr, diff, fn) {
  if (typeof diff === 'function') { fn = diff; diff = 1; }
  const evalExpr = (e) => typeof e === 'function' ? e() : eval(e.replace(/::/g, '.'));
  const before = await evalExpr(expr);
  await fn();
  const after = await evalExpr(expr);
  const { expect } = await import('vitest');
  expect(after - before).toBe(diff);
};

// assert_no_difference(expression, fn)
globalThis.assert_no_difference = async function(expr, fn) {
  return assert_difference(expr, 0, fn);
};

// assert_changes(expression, opts_or_fn, fn) - verify a value change
globalThis.assert_changes = async function(expr, ...args) {
  let fn = args.pop();
  const evalExpr = (e) => typeof e === 'function' ? e() : eval(e.replace(/::/g, '.'));
  const before = await evalExpr(expr);
  await fn();
  const after = await evalExpr(expr);
  const { expect } = await import('vitest');
  expect(after).not.toEqual(before);
};

// assert_no_changes(expression, fn)
globalThis.assert_no_changes = async function(expr, fn) {
  const evalExpr = (e) => typeof e === 'function' ? e() : eval(e.replace(/::/g, '.'));
  const before = await evalExpr(expr);
  await fn();
  const after = await evalExpr(expr);
  const { expect } = await import('vitest');
  expect(after).toEqual(before);
};

// mock()/stub() - Minitest/Mocha mock+stub framework
function _createStubChain(returnVal) {
  const chain = {
    _returnVal: returnVal,
    _yieldFn: null,
    _multiYields: null,
    returns(val) { chain._returnVal = val; return chain; },
    yields(...args) { chain._yieldFn = args; return chain; },
    multiple_yields(...args) { chain._multiYields = args; return chain; },
    with(...args) { return chain; },
    once() { return chain; },
    twice() { return chain; },
    at_least_once() { return chain; },
    never() { return chain; },
    then() { return chain; }
  };
  return chain;
}

globalThis.mock = function(name) {
  const obj = {
    _name: name || 'mock',
    stubs(method) { return _createStubChain(undefined); },
    expects(method) { return _createStubChain(undefined); },
    verify() { return true; }
  };
  return new Proxy(obj, {
    get(target, prop) {
      if (prop in target) return target[prop];
      return function() { return undefined; };
    }
  });
};

globalThis.stub = function(attrs) {
  if (attrs && typeof attrs === 'object') {
    const obj = { ...attrs };
    obj.stubs = function(method) { return _createStubChain(undefined); };
    obj.expects = function(method) { return _createStubChain(undefined); };
    return obj;
  }
  return _createStubChain(undefined);
};

// Add stubs/expects to all objects and classes for Mocha-style mocking
if (!Object.prototype.stubs) {
  Object.defineProperty(Object.prototype, 'stubs', {
    value: function(method) { return _createStubChain(undefined); },
    writable: true, configurable: true, enumerable: false
  });
}
if (!Object.prototype.expects) {
  Object.defineProperty(Object.prototype, 'expects', {
    value: function(method) { return _createStubChain(undefined); },
    writable: true, configurable: true, enumerable: false
  });
}

// stub_request - WebMock-style HTTP stubbing
globalThis.stub_request = function(method, url) {
  return _createStubChain({ code: '200', body: '' });
};
globalThis.assert_requested = function(stub) { /* no-op */ };

// freeze_time / travel_to / travel_back - time helpers (no-op stubs)
globalThis.freeze_time = async function(fn) { if (fn) await fn(); };
globalThis.travel_to = async function(time, fn) { if (fn) await fn(); };
globalThis.travel_back = function() {};

// perform_enqueued_jobs - ActiveJob test helper (runs block immediately)
globalThis.perform_enqueued_jobs = async function(fn) { if (fn) await fn(); };

// file_fixture - Rails test file fixture (stub)
globalThis.file_fixture = function(name) {
  return {
    read() { return ''; },
    path: name,
    toString() { return name; }
  };
};

// Tempfile stub
globalThis.Tempfile = class Tempfile {
  constructor(args) {
    this._name = Array.isArray(args) ? args[0] : args;
    this._content = '';
  }
  write(data) { this._content += data; }
  rewind() {}
  read() { return this._content; }
  close() {}
  unlink() {}
  get path() { return '/tmp/' + this._name; }
};

// StringIO stub - Ruby stdlib in-memory IO
globalThis.StringIO = class StringIO {
  constructor(str) { this._str = str || ''; this._pos = 0; }
  write(data) { this._str += data; return data.length; }
  read() { return this._str; }
  rewind() { this._pos = 0; }
  string() { return this._str; }
  toString() { return this._str; }
};

// Net namespace - Ruby stdlib networking
globalThis.Net = {
  HTTP: Object.assign(function() {}, {
    get(url) { return ''; },
    post(url, body) { return ''; },
    new(...args) { return mock('http'); },
    start(...args) { return mock('http'); }
  })
};

// Resolv namespace - Ruby stdlib DNS resolution
globalThis.Resolv = {
  DNS: Object.assign(function() {}, {
    open(...args) { return []; },
    new() { return { getaddress() { return '127.0.0.1'; } }; }
  })
};

// assert_turbo_stream_broadcasts - Turbo test helper (no-op)
globalThis.assert_turbo_stream_broadcasts = function() {};
globalThis.assert_no_turbo_stream_broadcasts = function() {};

// ActiveJob test helpers
globalThis.assert_enqueued_with = function() {};
globalThis.assert_enqueued_jobs = function(count, fn) { if (fn) return fn(); };
globalThis.assert_no_enqueued_jobs = function(fn) { if (fn) return fn(); };
`;
}

/**
 * Get the active record adapter filename for a database.
 */
function getActiveRecordAdapterFile(database) {
  const adapterMap = {
    'sqlite': 'active_record_sqlite.mjs',
    'sqlite3': 'active_record_sqlite.mjs',
    'better_sqlite3': 'active_record_better_sqlite3.mjs',
    'dexie': 'active_record_dexie.mjs',
    'pg': 'active_record_pg.mjs',
    'postgres': 'active_record_pg.mjs',
    'neon': 'active_record_neon.mjs',
    'd1': 'active_record_d1.mjs',
    'turso': 'active_record_turso.mjs',
    'pglite': 'active_record_pglite.mjs',
    'sqljs': 'active_record_sqljs.mjs',
    'mysql': 'active_record_mysql2.mjs',
    'mysql2': 'active_record_mysql2.mjs'
  };
  return adapterMap[database] || 'active_record_dexie.mjs';
}

/**
 * Generate main.js entry point for ejected Node.js server.
 */
export function generateMainJsForEject(config = {}) {
  const adapterFile = getActiveRecordAdapterFile(config.database);
  const dbConfig = config.database === 'sqlite' || config.database === 'sqlite3' || config.database === 'better_sqlite3'
    ? `{ adapter: 'better_sqlite3', database: './db/development.sqlite3' }`
    : `{ adapter: '${config.database || 'dexie'}', database: 'app_dev' }`;

  // Determine target for importing Application
  let target = config.target || 'node';
  if (!config.target && config.database === 'dexie') {
    target = 'browser';
  }
  const railsModule = `ruby2js-rails/targets/${target}/rails.js`;

  return `// Main entry point for ejected Node.js server
import { Application, Router } from '${railsModule}';
import * as activeRecord from 'ruby2js-rails/adapters/${adapterFile}';

// Import models (registers them)
import './app/models/index.js';

// Import migrations and seeds
import { migrations } from './db/migrate/index.js';
import { Seeds } from './db/seeds.js';

// Import routes (sets up the router)
import './config/routes.js';

async function main() {
  // Configure application
  Application.configure({ migrations });

  // Initialize database
  console.log('Initializing database...');
  await activeRecord.initDatabase(${dbConfig});

  // Run migrations
  console.log('Running migrations...');
  await Application.runMigrations(activeRecord);

  // Run seeds if database is fresh
  if (Seeds && typeof Seeds.run === 'function') {
    console.log('Running seeds...');
    await Seeds.run();
  }

  // Start server
  const port = process.env.PORT || 3000;
  console.log(\`Starting server on http://localhost:\${port}\`);

  // Create HTTP server with Router dispatch
  const { createServer } = await import('http');
  const server = createServer(async (req, res) => {
    await Router.dispatch(req, res);
  });

  server.listen(port);
}

main().catch(console.error);
`;
}

/**
 * Generate vitest.config.js for ejected output.
 */
export function generateVitestConfigForEject(config = {}) {
  const externals = [];

  // Native/built-in modules need to be externalized for Vite/Vitest
  if (config.database === 'better_sqlite3') {
    externals.push('better-sqlite3');
  } else if (config.database === 'sqlite' || config.database === 'sqlite3') {
    externals.push('node:sqlite');
  }

  const serverDepsConfig = externals.length > 0
    ? `\n    server: {\n      deps: {\n        external: ${JSON.stringify(externals)}\n      }\n    },`
    : '';

  return `import { defineConfig } from 'vitest/config';
import { fileURLToPath } from 'url';
import { dirname, resolve } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));

export default defineConfig({
  test: {
    root: __dirname,
    globals: true,
    environment: 'node',${serverDepsConfig}
    include: ['test/**/*.test.mjs', 'test/**/*.test.js'],
    setupFiles: [resolve(__dirname, 'test/globals.mjs'), resolve(__dirname, 'test/setup.mjs')]
  }
});
`;
}

/**
 * Generate vite.config.js for ejected output.
 * This is a plain Vite config - no ruby2js plugins needed since code is already JS.
 */
export function generateViteConfigForEject(config = {}) {
  const adapterFile = getActiveRecordAdapterFile(config.database);

  // Determine if this is a browser target
  const browserTargets = ['browser', 'pwa', 'capacitor', 'electron', 'tauri'];
  const isBrowserTarget = browserTargets.includes(config.target);

  // Build aliases - always include app paths
  const aliases = [
    `      'app/': './app/'`,
    `      'config/': './config/'`,
    `      'db/': './db/'`
  ];

  // Add virtual module aliases for browser targets
  if (isBrowserTarget) {
    aliases.push(`      'juntos:active-record': 'ruby2js-rails/adapters/${adapterFile}'`);
  }

  return `import { defineConfig } from 'vite';

export default defineConfig({
  // Ejected JavaScript - no ruby2js transformation needed
  resolve: {
    alias: {
${aliases.join(',\n')}
    }
  }
});
`;
}

/**
 * Generate index.html for browser builds.
 * Used by both Vite plugin (dev) and eject command (standalone).
 * @param {string} appName - Application name for the title
 * @param {string} mainJsPath - Path to main.js (e.g., '/.browser/main.js' or './main.js')
 */
export function generateBrowserIndexHtml(appName, mainJsPath = './main.js') {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${appName}</title>
  <link rel="icon" href="data:,">
  <link href="/app/assets/builds/tailwind.css" rel="stylesheet">
</head>
<body>
  <div id="loading">Loading...</div>
  <div id="app" style="display:none">
    <main class="container mx-auto mt-28 px-5" id="content"></main>
  </div>
  <script type="module" src="${mainJsPath}"></script>
</body>
</html>
`;
}

/**
 * Generate main.js entry point for browser builds.
 * Used by both Vite plugin (dev) and eject command (standalone).
 * @param {string} routesPath - Import path for routes (e.g., '../config/routes.rb' or './config/routes.js')
 * @param {string} controllersPath - Import path for controllers (e.g., '../app/javascript/controllers/index.js')
 */
export function generateBrowserMainJs(routesPath = './config/routes.js', controllersPath = './app/javascript/controllers/index.js') {
  return `// Main entry point for browser
import * as Turbo from '@hotwired/turbo';
import { Application } from '${routesPath}';
import '${controllersPath}';
window.Turbo = Turbo;
Application.start();
`;
}

/**
 * Generate content for juntos:migrations virtual module.
 */
export function generateMigrationsModule(appRoot) {
  const migrations = findMigrations(appRoot);
  const imports = migrations.map((m, i) =>
    `import { migration as migration${i} } from 'db/migrate/${m.file}';`
  );
  const exports = migrations.map((m, i) =>
    `{ version: '${m.name.split('_')[0]}', name: '${m.name}', ...migration${i} }`
  );
  return `${imports.join('\n')}
export const migrations = [${exports.join(', ')}];
`;
}

/**
 * Generate content for juntos:migrations for ejected output.
 */
export function generateMigrationsModuleForEject(appRoot) {
  const migrations = findMigrations(appRoot);
  const imports = migrations.map((m, i) =>
    `import { migration as migration${i} } from './${m.name}.js';`
  );
  const exports = migrations.map((m, i) =>
    `{ version: '${m.name.split('_')[0]}', name: '${m.name}', ...migration${i} }`
  );
  return `${imports.join('\n')}
export const migrations = [${exports.join(', ')}];
`;
}

/**
 * Deduplicate view exports when a partial and non-partial share the same name.
 * E.g., _index.html.erb and index.html.erb both produce exportName "index".
 * Non-partials win; partials keep their _ prefix to avoid collision.
 */
function deduplicateViewExports(views) {
  const seen = new Set();
  // First pass: collect non-partial export names
  for (const v of views) {
    if (!v.isPartial) seen.add(v.exportName);
  }
  // Second pass: rename partials that conflict with non-partials
  for (const v of views) {
    if (v.isPartial && seen.has(v.exportName)) {
      v.exportName = '_' + v.exportName;
    }
    seen.add(v.exportName);
  }
  return views;
}

/**
 * Generate content for juntos:views/* virtual module.
 * @param {string} appRoot - Application root
 * @param {string} resource - Resource name (e.g., 'articles', 'workflows')
 * @returns {string} Module content
 */
export function generateViewsModule(appRoot, resource) {
  const viewsDir = path.join(appRoot, 'app/views', resource);
  if (!fs.existsSync(viewsDir)) return `export const ${capitalize(resource)}Views = {};`;

  // Collect ERB views (.html.erb)
  const erbViews = fs.readdirSync(viewsDir)
    .filter(f => f.endsWith('.html.erb') && !f.startsWith('._'))
    .map(f => {
      const name = f.replace('.html.erb', '');
      const isPartial = name.startsWith('_');
      let exportName = isPartial ? name.slice(1) : name;
      // Escape reserved words by adding $ prefix (matches Ruby2JS convention)
      if (RESERVED.has(exportName)) exportName = '$' + exportName;
      return { file: f, name, exportName, isPartial, isReact: false };
    });

  // Collect React views (.jsx.rb) - these export default, not render
  const reactViews = fs.readdirSync(viewsDir)
    .filter(f => f.endsWith('.jsx.rb') && !f.startsWith('._'))
    .map(f => {
      // Show.jsx.rb -> show (lowercase)
      const name = f.replace('.jsx.rb', '');
      let exportName = name.toLowerCase();
      if (RESERVED.has(exportName)) exportName = '$' + exportName;
      return { file: f, name, exportName, isPartial: false, isReact: true };
    });

  const views = deduplicateViewExports([...erbViews, ...reactViews]);

  const imports = views.map(v => {
    if (v.isReact) {
      // React components export default
      return `import ${v.exportName} from 'app/views/${resource}/${v.file}';`;
    } else {
      // ERB views export { render }
      return `import { render as ${v.exportName} } from 'app/views/${resource}/${v.file}';`;
    }
  });

  // Create namespace object: ArticleViews = { index, show, new_, edit, ... }
  // Use singularized form to match controller filter (ArticleViews, not ArticlesViews)
  const className = capitalize(singularize(resource)) + 'Views';
  const members = views.map(v => v.exportName);

  return `${imports.join('\n')}
export const ${className} = { ${members.join(', ')} };
export { ${members.join(', ')} };
`;
}

/**
 * Generate content for views module for ejected output.
 */
export function generateViewsModuleForEject(appRoot, resource) {
  const viewsDir = path.join(appRoot, 'app/views', resource);
  if (!fs.existsSync(viewsDir)) return `export const ${capitalize(resource)}Views = {};`;

  // Collect ERB views (.html.erb)
  const erbViews = fs.readdirSync(viewsDir)
    .filter(f => f.endsWith('.html.erb') && !f.startsWith('._'))
    .map(f => {
      const name = f.replace('.html.erb', '');
      const isPartial = name.startsWith('_');
      let exportName = isPartial ? name.slice(1) : name;
      if (RESERVED.has(exportName)) exportName = '$' + exportName;
      // Output filename: index.html.erb → index.js
      const outputFile = f.replace('.html.erb', '.js');
      return { file: f, outputFile, name, exportName, isPartial, isReact: false };
    });

  // Collect React views (.jsx.rb)
  const reactViews = fs.readdirSync(viewsDir)
    .filter(f => f.endsWith('.jsx.rb') && !f.startsWith('._'))
    .map(f => {
      const name = f.replace('.jsx.rb', '');
      let exportName = name.toLowerCase();
      if (RESERVED.has(exportName)) exportName = '$' + exportName;
      // Output filename: Show.jsx.rb → Show.js
      const outputFile = f.replace('.jsx.rb', '.js');
      return { file: f, outputFile, name, exportName, isPartial: false, isReact: true };
    });

  const views = deduplicateViewExports([...erbViews, ...reactViews]);

  const imports = views.map(v => {
    if (v.isReact) {
      return `import ${v.exportName} from './${resource}/${v.outputFile}';`;
    } else {
      return `import { render as ${v.exportName} } from './${resource}/${v.outputFile}';`;
    }
  });

  const className = capitalize(singularize(resource)) + 'Views';
  const members = views.map(v => v.exportName);

  return `${imports.join('\n')}
export const ${className} = { ${members.join(', ')} };
export { ${members.join(', ')} };
`;
}

// ============================================================
// Transformation functions
// ============================================================

// Lazy-loaded ruby2js module
let ruby2jsModule = null;
let filtersLoaded = false;

/**
 * Ensure ruby2js module is loaded, Prism is initialized, and filters are loaded.
 */
export async function ensureRuby2jsReady() {
  if (!ruby2jsModule) {
    ruby2jsModule = await import('ruby2js');
    await ruby2jsModule.initPrism();
  }

  // Load all filters needed for Rails apps (used by both Vite and eject)
  if (!filtersLoaded) {
    // Core filters
    await import('ruby2js/filters/active_support.js');
    await import('ruby2js/filters/functions.js');
    await import('ruby2js/filters/esm.js');
    await import('ruby2js/filters/return.js');
    await import('ruby2js/filters/pragma.js');
    await import('ruby2js/filters/polyfill.js');

    // Rails filters
    await import('ruby2js/filters/rails/concern.js');
    await import('ruby2js/filters/rails/model.js');
    await import('ruby2js/filters/rails/controller.js');
    await import('ruby2js/filters/rails/routes.js');
    await import('ruby2js/filters/rails/seeds.js');
    await import('ruby2js/filters/rails/migration.js');
    await import('ruby2js/filters/rails/helpers.js');
    await import('ruby2js/filters/rails/test.js');

    // Template filters
    await import('ruby2js/filters/erb.js');

    // Component filters
    await import('ruby2js/filters/react.js');
    await import('ruby2js/filters/stimulus.js');

    // Node.js filter (File operations, backtick commands, etc.)
    await import('ruby2js/filters/node.js');

    filtersLoaded = true;
  }

  return ruby2jsModule;
}

/**
 * Transform Ruby source to JavaScript.
 *
 * @param {string} source - Ruby source code
 * @param {string} filePath - Path to source file (for sourcemaps)
 * @param {string} section - Transformation section (stimulus, controllers, jsx, or null for default)
 * @param {Object} config - Configuration object with target, database, base, etc.
 * @param {string} appRoot - Application root directory
 * @returns {Promise<{code: string, map: Object}>}
 */
export async function transformRuby(source, filePath, section, config, appRoot) {
  const { convert } = await ensureRuby2jsReady();

  // Get section-specific config from ruby2js.yml if available
  const sectionConfig = config.sections?.[section] || null;
  const options = {
    ...getBuildOptions(section, config.target, sectionConfig),
    file: path.relative(appRoot, filePath),
    database: config.database,
    target: config.target
  };

  // Routes need additional options
  if (filePath.endsWith('/routes.rb')) {
    options.base = config.base || '/';
  }

  const result = convert(source, options);
  return {
    code: result.toString(),
    map: result.sourcemap
  };
}

/**
 * Transform ERB template to JavaScript.
 *
 * @param {string} code - ERB source code
 * @param {string} id - File path
 * @param {boolean} isLayout - Whether this is a layout file
 * @param {Object} config - Configuration object
 * @returns {Promise<{code: string, map: Object|null}>}
 */
export async function transformErb(code, id, isLayout, config) {
  const { convert } = await ensureRuby2jsReady();

  let template = code;

  // Step 1: Compile ERB to Ruby
  const compiler = new ErbCompiler(template);
  const rubySrc = compiler.src;

  // Step 2: Convert Ruby to JavaScript with ERB filters
  const nodeTargets = ['node', 'bun', 'deno', 'fly', 'electron'];
  const nodeFilter = config.target && nodeTargets.includes(config.target) ? ['Node'] : [];
  const options = {
    filters: ['Rails_Helpers', 'Erb', ...nodeFilter, 'Functions', 'Return'],
    eslevel: config.eslevel || 2022,
    include: ['class', 'call'],
    database: config.database,
    target: config.target,
    file: id
  };

  if (isLayout) {
    options.layout = true;
  }

  const result = convert(rubySrc, options);

  // Step 3: Export the function
  let js = result.toString();
  if (isLayout) {
    js = js.replace(/(^|\n)(async )?function layout/, '$1export $2function layout');
  } else {
    js = js.replace(/(^|\n)(async )?function render/, '$1export $2function render');
  }

  return {
    code: js,
    map: result.sourcemap || null
  };
}

/**
 * Transform JSX.rb (Ruby + JSX) to JavaScript.
 *
 * @param {string} source - Ruby + JSX source code
 * @param {string} filePath - File path
 * @param {Object} config - Configuration object
 * @returns {Promise<{code: string, map: Object|null}>}
 */
export async function transformJsxRb(source, filePath, config) {
  const { convert } = await ensureRuby2jsReady();

  // Get section-specific config from ruby2js.yml if available
  const sectionConfig = config.sections?.jsx || null;
  const options = {
    ...getBuildOptions('jsx', config.target, sectionConfig),
    file: filePath
  };

  const result = convert(source, options);
  return {
    code: result.toString(),
    map: result.sourcemap || null
  };
}

// Re-export ErbCompiler for direct use if needed
export { ErbCompiler };
