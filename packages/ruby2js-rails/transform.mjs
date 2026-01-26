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
 */
export function getBuildOptions(section, target) {
  const baseOptions = {
    eslevel: 2022,
    include: ['class', 'call']
  };

  switch (section) {
    case 'stimulus':
      return {
        ...baseOptions,
        autoexports: 'default',
        filters: ['Pragma', 'Stimulus', 'Functions', 'ESM', 'Return'],
        target
      };

    case 'controllers':
      return {
        ...baseOptions,
        autoexports: true,
        filters: ['Rails_Controller', 'Functions', 'ESM', 'Return'],
        target
      };

    case 'jsx':
      return {
        ...baseOptions,
        autoexports: 'default',
        filters: ['React', 'Functions', 'ESM', 'Return'],
        target
      };

    default:
      // Models, routes, seeds, migrations
      return {
        ...baseOptions,
        autoexports: true,
        filters: ['Rails_Model', 'Rails_Controller', 'Rails_Routes', 'Rails_Seeds', 'Rails_Migration', 'Functions', 'ESM', 'Return'],
        target
      };
  }
}

// ============================================================
// File discovery
// ============================================================

/**
 * Find all model files in app/models/.
 * Returns array of model names (without .rb extension).
 */
export function findModels(appRoot) {
  const modelsDir = path.join(appRoot, 'app/models');
  if (!fs.existsSync(modelsDir)) return [];
  return fs.readdirSync(modelsDir)
    .filter(f => f.endsWith('.rb') && f !== 'application_record.rb' && !f.startsWith('._'))
    .map(f => f.replace('.rb', ''));
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

  // Model imports: .js → .rb (same directory)
  js = js.replace(/from ['"]\.\/(\w+)\.js['"]/g, (match, name) => {
    if (name === 'application_record') return "from 'juntos:application-record'";
    return `from './${name}.rb'`;
  });

  // Model imports from controllers: ../models/*.js → ../models/*.rb
  js = js.replace(/from ['"]\.\.\/models\/(\w+)\.js['"]/g, "from '../models/$1.rb'");

  // Views: ../views/*.js → juntos:views/*
  js = js.replace(/from ['"]\.\.\/views\/(\w+)\.js['"]/g, "from 'juntos:views/$1'");
  js = js.replace(/from ['"]\.\.\/views\/(\w+)\/([\w_]+)\.js['"]/g, "from 'app/views/$1/$2.html.erb'");

  // Config: ../../config/paths.js → juntos:paths (inline in routes)
  js = js.replace(/from ['"]\.\.\/\.\.\/config\/paths\.js['"]/g, "from 'config/routes.rb'");
  js = js.replace(/from ['"]\.\/paths\.js['"]/g, "from 'config/routes.rb'");

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
 * Fix imports for ejected code - rewrites to use ruby2js-rails package.
 * Ejected code depends on the juntos runtime, not copied local files.
 */
export function fixImportsForEject(js, fromFile) {
  // Runtime modules → ruby2js-rails package
  js = js.replace(/from ['"]\.\.\/lib\/rails\.js['"]/g, "from 'ruby2js-rails/rails_base.js'");
  js = js.replace(/from ['"]\.\.\/\.\.\/lib\/rails\.js['"]/g, "from 'ruby2js-rails/rails_base.js'");
  js = js.replace(/from ['"]\.\.\/\.\.\/\.\.\/lib\/rails\.js['"]/g, "from 'ruby2js-rails/rails_base.js'");
  js = js.replace(/from ['"]\.\.\/lib\/active_record\.mjs['"]/g, "from 'ruby2js-rails/adapters/active_record.mjs'");
  js = js.replace(/from ['"]\.\.\/\.\.\/lib\/active_record\.mjs['"]/g, "from 'ruby2js-rails/adapters/active_record.mjs'");

  // ApplicationRecord → local file (generated separately)
  js = js.replace(/from ['"]\.\/application_record\.js['"]/g, "from './application_record.js'");

  // Model imports: .js extension for ejected files
  js = js.replace(/from ['"]\.\/(\w+)\.js['"]/g, "from './$1.js'");

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
  const imports = models.map(m => {
    const className = m.split('_').map(s => s[0].toUpperCase() + s.slice(1)).join('');
    return `import { ${className} } from 'app/models/${m}.rb';`;
  });
  const classNames = models.map(m =>
    m.split('_').map(s => s[0].toUpperCase() + s.slice(1)).join('')
  );
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
export function generateModelsModuleForEject(appRoot) {
  const models = findModels(appRoot);
  const imports = models.map(m => {
    const className = m.split('_').map(s => s[0].toUpperCase() + s.slice(1)).join('');
    return `import { ${className} } from './${m}.js';`;
  });
  const classNames = models.map(m =>
    m.split('_').map(s => s[0].toUpperCase() + s.slice(1)).join('')
  );
  return `${imports.join('\n')}
import { Application } from 'ruby2js-rails/rails_base.js';
import { modelRegistry } from 'ruby2js-rails/adapters/active_record.mjs';
const models = { ${classNames.join(', ')} };
Application.registerModels(models);
Object.assign(modelRegistry, models);
export { ${classNames.join(', ')} };
`;
}

/**
 * Generate application_record.js for ejected output.
 * This provides the base class for all models.
 */
export function generateApplicationRecordForEject() {
  return `import { ApplicationRecord as Base, CollectionProxy } from 'ruby2js-rails/adapters/active_record.mjs';

export class ApplicationRecord extends Base {
  static primaryAbstractClass = true;
}

export { CollectionProxy };
`;
}

/**
 * Generate package.json for ejected output.
 */
export function generatePackageJsonForEject(appName) {
  return JSON.stringify({
    name: appName,
    type: 'module',
    scripts: {
      dev: 'vite',
      build: 'vite build',
      preview: 'vite preview'
    },
    dependencies: {
      'ruby2js-rails': '*',
      'react': '^18.0.0',
      'react-dom': '^18.0.0'
    },
    devDependencies: {
      'vite': '^6.0.0'
    }
  }, null, 2) + '\n';
}

/**
 * Generate vite.config.js for ejected output.
 * This is a plain Vite config - no ruby2js plugins needed since code is already JS.
 */
export function generateViteConfigForEject() {
  return `import { defineConfig } from 'vite';

export default defineConfig({
  // Ejected JavaScript - no ruby2js transformation needed
  resolve: {
    alias: {
      // Map app paths for cleaner imports
      'app/': './app/',
      'config/': './config/',
      'db/': './db/'
    }
  }
});
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

  const views = [...erbViews, ...reactViews];

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

  const views = [...erbViews, ...reactViews];

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
    await import('ruby2js/filters/functions.js');
    await import('ruby2js/filters/esm.js');
    await import('ruby2js/filters/return.js');
    await import('ruby2js/filters/pragma.js');

    // Rails filters
    await import('ruby2js/filters/rails/model.js');
    await import('ruby2js/filters/rails/controller.js');
    await import('ruby2js/filters/rails/routes.js');
    await import('ruby2js/filters/rails/seeds.js');
    await import('ruby2js/filters/rails/migration.js');
    await import('ruby2js/filters/rails/helpers.js');

    // Template filters
    await import('ruby2js/filters/erb.js');

    // Component filters
    await import('ruby2js/filters/react.js');
    await import('ruby2js/filters/stimulus.js');

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

  const options = {
    ...getBuildOptions(section, config.target),
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

  // Handle layout yield transformations
  let template = code;
  if (isLayout) {
    template = template.replace(/<%= yield :(\w+) %>/g, "<%= context.contentFor.$1 || '' %>");
    template = template.replace(/<%= yield %>/g, '<%= content %>');
  }

  // Step 1: Compile ERB to Ruby
  const compiler = new ErbCompiler(template);
  const rubySrc = compiler.src;

  // Step 2: Convert Ruby to JavaScript with ERB filters
  const options = {
    filters: ['Rails_Helpers', 'Erb', 'Functions', 'Return'],
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

  const options = {
    ...getBuildOptions('jsx', config.target),
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
