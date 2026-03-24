/**
 * Shared import resolver for all Ruby2JS/Juntos pipelines.
 *
 * Replaces three separate import resolution code paths with a single
 * configurable resolver. Used by:
 * - Vite dev mode (mode: 'vite')
 * - Eject pipeline (mode: 'eject')
 * - Vitest (mode: 'vite')
 *
 * Each mode produces different output for the same input:
 * - Vite: .rb extensions, juntos:* virtual modules
 * - Eject: .js extensions, juntos/* package paths
 */

import { getActiveRecordAdapterFile } from './transform.mjs';

export class ImportResolver {
  #mode;        // 'vite' | 'eject'
  #fromFile;    // relative path of the source file
  #appRoot;     // absolute path to app root
  #config;      // { target, database, models, modelClassMap, controllerConcerns }
  #ext;         // '.rb' for vite, '.js' for eject
  #fileType;    // 'model' | 'controller' | 'helper' | 'view' | 'test' | 'config' | 'other'

  // Eject-mode computed values
  #target;
  #railsModule;
  #adapterFile;
  #rootPrefix;

  constructor({ mode, fromFile, appRoot, config = {} }) {
    this.#mode = mode;
    this.#fromFile = fromFile || '';
    this.#appRoot = appRoot || '.';
    this.#config = config;
    this.#ext = mode === 'vite' ? '.rb' : '.js';
    this.#fileType = this.#classifyFile();

    // Eject-mode target resolution
    if (mode === 'eject') {
      this.#target = config.target || 'node';
      if (!config.target && config.database === 'dexie') this.#target = 'browser';
      this.#railsModule = `juntos/targets/${this.#target}/rails.js`;
      this.#adapterFile = getActiveRecordAdapterFile(config.database);
      const depth = fromFile ? fromFile.split('/').length - 1 : 1;
      this.#rootPrefix = '../'.repeat(depth);
    }
  }

  /**
   * Main entry point: resolve all imports in a JS string.
   * @param {string} js - JavaScript source code
   * @returns {string} - Modified source with resolved imports
   */
  resolve(js) {
    // Step 1: Resolve all from '...' imports in a single pass
    js = js.replace(/from (['"])(.*?)\1/g, (match, quote, source) => {
      const resolved = this.#resolveSource(source);
      return resolved ? `from '${resolved}'` : match;
    });

    // Step 2: Add model cross-references (modelRegistry for both modes)
    if (this.#config.modelClassMap) {
      js = this.#addModelReferences(js);
    }

    // Step 3: Eject-only post-processing
    if (this.#mode === 'eject') {
      js = this.#fixNestedDepth(js);
      js = this.#rewriteUrlImports(js);
    }

    return js;
  }

  // ============================================================
  // File classification
  // ============================================================

  #classifyFile() {
    const f = this.#fromFile;
    if (f.includes('/models/') || f.includes('app/models/')) return 'model';
    if (f.includes('/controllers/') || f.includes('app/controllers/')) return 'controller';
    if (f.includes('/helpers/') || f.includes('app/helpers/')) return 'helper';
    if (f.includes('/views/') || f.includes('app/views/')) return 'view';
    if (f.includes('/test/') || f.startsWith('test/')) return 'test';
    if (f.includes('config/')) return 'config';
    return 'other';
  }

  // ============================================================
  // Single import source resolution
  // ============================================================

  #resolveSource(source) {
    // --- Virtual modules (both modes recognize, resolve differently) ---

    // Runtime: ../lib/rails.js (any depth) or juntos:rails
    if (/^(?:\.\.\/)+lib\/rails\.js$/.test(source) || source === 'juntos:rails') {
      return this.#mode === 'vite' ? 'juntos:rails' : this.#railsModule;
    }

    // Active Record: ../lib/active_record.mjs (any depth) or juntos:active-record
    if (/^(?:\.\.\/)+lib\/active_record\.mjs$/.test(source) || source === 'juntos:active-record') {
      return this.#mode === 'vite' ? 'juntos:active-record' : `juntos/adapters/${this.#adapterFile}`;
    }

    // Rails base aliases
    if (source === 'ruby2js-rails/rails_base.js' || source === 'juntos/rails_base.js' ||
        source === 'lib/rails.js') {
      return this.#mode === 'vite' ? 'juntos:rails' : this.#railsModule;
    }

    // Active Storage virtual module
    if (source === 'juntos:active-storage') {
      return this.#mode === 'vite' ? source : 'juntos/adapters/active_storage_base.mjs';
    }

    // URL helpers virtual module
    if (source === 'juntos:url-helpers') {
      return this.#mode === 'vite' ? source : 'juntos/url_helpers.mjs';
    }

    // Config paths → virtual module or depth-relative
    if (/^(?:\.\.\/)+config\/paths\.js$/.test(source) || source === './paths.js') {
      return this.#mode === 'vite' ? 'juntos:paths' : `${this.#rootPrefix}config/paths.js`;
    }
    if (source === '@config/paths.js') {
      return this.#mode === 'vite' ? 'juntos:paths' : `${this.#rootPrefix}config/paths.js`;
    }

    // Migrations → virtual module or depth-relative
    if (/^(?:\.\.\/)+db\/migrate\/index\.js$/.test(source)) {
      return this.#mode === 'vite' ? 'juntos:migrations' : `${this.#rootPrefix}db/migrate/index.js`;
    }

    // Seeds
    if (/^(?:\.\.\/)+db\/seeds\.js$/.test(source)) {
      return this.#mode === 'vite' ? 'db/seeds.rb' : `${this.#rootPrefix}db/seeds.js`;
    }

    // Models index → virtual module or depth-relative
    if (/^(?:\.\.\/)+app\/models\/index\.js$/.test(source)) {
      return this.#mode === 'vite' ? 'juntos:models' : `${this.#rootPrefix}app/models/index.js`;
    }
    if (source === './index.js' && this.#fileType === 'model') {
      return this.#mode === 'vite' ? 'juntos:models' : null;
    }

    // Layout
    if (/^(?:\.\.\/)+app\/views\/layouts\/application\.js$/.test(source)) {
      return this.#mode === 'vite' ? '@views/layouts/application.html.erb' : null;
    }

    // --- @-prefixed aliases ---

    // @helpers/*.js or @helpers/*.rb
    const helperMatch = source.match(/^@helpers\/([\w]+)\.(js|rb)$/);
    if (helperMatch) {
      const name = helperMatch[1];
      return this.#mode === 'vite' ? `@helpers/${name}.rb` : `${this.#rootPrefix}app/helpers/${name}.js`;
    }

    // --- View imports (barrels vs partials) ---
    const viewMatch = source.match(/^(?:\.\.\/)+views\/([\w/]+)\.js$/);
    if (viewMatch) {
      const viewPath = viewMatch[1];
      const lastSegment = viewPath.split('/').pop();
      if (lastSegment.startsWith('_')) {
        // Partials → ERB source (vite) or relative .js (eject — handled by nested depth)
        return this.#mode === 'vite' ? `app/views/${viewPath}.html.erb` : null;
      }
      // View barrels → virtual module (vite) or leave for barrel file (eject)
      return this.#mode === 'vite' ? `juntos:views/${viewPath}` : null;
    }

    // --- Controllers from routes ---
    const ctrlMatch = source.match(/^(?:\.\.\/)+app\/controllers\/([\w/]+)\.js$/);
    if (ctrlMatch) {
      return this.#mode === 'vite' ? `app/controllers/${ctrlMatch[1]}.rb` : null;
    }

    // --- Model imports from controllers ---
    const modelFromCtrl = source.match(/^\.\.\/models\/([\w/]+)\.js$/);
    if (modelFromCtrl) {
      return this.#mode === 'vite' ? `../models/${modelFromCtrl[1]}.rb` : null;
    }

    // --- Same-directory .js → .rb (vite only) ---
    if (this.#mode === 'vite') {
      const localJs = source.match(/^\.\/([\w/]+)\.js$/);
      if (localJs) return `./${localJs[1]}.rb`;
    }

    // --- Eject-only static mappings ---
    if (this.#mode === 'eject') {
      // juntos:rails virtual module (already resolved by eject pipeline)
      if (source === 'juntos:rails') return this.#railsModule;
    }

    return null;
  }

  // ============================================================
  // Model cross-references (shared between modes)
  // ============================================================

  /**
   * Scan for bare ClassName.method or new ClassName( references to known
   * models and rewrite to modelRegistry.ClassName. Prevents circular imports.
   */
  #addModelReferences(js) {
    const modelClassMap = this.#config.modelClassMap;
    if (!modelClassMap) return js;

    // Determine current file's model path (for self-reference skip)
    let currentModelPath = null;
    if (this.#fileType === 'model') {
      currentModelPath = this.#fromFile
        .replace(/^.*app\/models\//, '')
        .replace(/\.(js|rb)$/, '');
    }

    for (const [className, modelPath] of Object.entries(modelClassMap)) {
      // Skip if already imported
      const importPattern = new RegExp(`import\\s+\\{[^}]*\\b${className}\\b[^}]*\\}\\s+from`);
      if (importPattern.test(js)) continue;

      // Skip self-references
      if (currentModelPath && modelPath === currentModelPath) continue;

      // Skip if this file defines/exports this class
      const definesClass = new RegExp(`(export\\s+)?(class|const|let|var|function)\\s+${className}\\b`);
      if (definesClass.test(js)) continue;

      // Skip references to models in a subdirectory named after this file
      // (prevents circular dependency with subclasses)
      if (currentModelPath) {
        const baseName = currentModelPath.split('/').pop();
        if (modelPath.startsWith(currentModelPath.replace(/[^/]+$/, baseName + '/'))) continue;
      }

      // Check if this class name is referenced
      const refPattern = new RegExp(`(?<!\\.)\\b${className}\\b(?=\\.)`, 'g');
      if (!refPattern.test(js)) continue;

      // Ensure modelRegistry is imported
      if (!js.includes('modelRegistry')) {
        if (this.#mode === 'vite') {
          // Vite: import from application_record.rb
          js = `import { modelRegistry } from 'app/models/application_record.rb';\n${js}`;
        } else {
          // Eject: import from relative application_record.js
          const depth = currentModelPath ? currentModelPath.split('/').length - 1 : 0;
          const prefix = depth > 0 ? '../'.repeat(depth) : './';
          js = `import { modelRegistry } from '${prefix}application_record.js';\n${js}`;
        }
      }

      // Replace bare ClassName references with modelRegistry.ClassName
      js = js.replace(new RegExp(`(?<!\\.)\\b${className}\\b(?=\\.)`, 'g'), `modelRegistry.${className}`);
    }

    return js;
  }

  // ============================================================
  // Eject-only: nested depth adjustments
  // ============================================================

  #fixNestedDepth(js) {
    const fromFile = this.#fromFile;
    if (!fromFile) return js;

    // Nested model files: ./ imports → ../ adjusted
    if (fromFile.startsWith('app/models/')) {
      const modelRelPath = fromFile.replace('app/models/', '');
      const depth = modelRelPath.split('/').length - 1;
      if (depth > 0) {
        const prefix = '../'.repeat(depth);
        js = js.replace(/from ['"]\.\/([\w/]+\.js)['"]/g, `from '${prefix}$1'`);
      }
    }

    // Controller files: concern routing + nested depth
    if (fromFile.startsWith('app/controllers/')) {
      const controllerConcerns = this.#config.controllerConcerns;
      const concernFallbackPatterns = ['scoped', 'authentication', 'authorization'];
      js = js.replace(/from ['"]\.\.\/models\/([\w]+)\.js['"]/g, (match, name) => {
        if (controllerConcerns) {
          if (controllerConcerns.has(name)) return `from './concerns/${name}.js'`;
        } else {
          const isLikelyConcern = concernFallbackPatterns.some(p => name.toLowerCase().includes(p));
          if (isLikelyConcern) return `from './concerns/${name}.js'`;
        }
        return match;
      });

      const ctrlRelPath = fromFile.replace('app/controllers/', '');
      const depth = ctrlRelPath.split('/').length - 1;
      if (depth > 0) {
        const prefix = '../'.repeat(depth);
        js = js.replace(/from ['"]((?:\.\.\/)+)([\w/]+\.(?:js|mjs))['"]/g,
          (match, dots, path) => `from '${prefix}${dots}${path}'`);
        js = js.replace(/from ['"]\.\/([\w/]+\.(?:js|mjs))['"]/g, `from '${prefix}$1'`);
      }
    }

    return js;
  }

  // ============================================================
  // Eject-only: _url → _path rewriting in path helper imports
  // ============================================================

  #rewriteUrlImports(js) {
    return js.replace(/import\s*\{([^}]+)\}\s*from\s*(['"])(.*?paths\.js)\2/g, (match, names, quote, source) => {
      const rewritten = names.replace(/(\w+)_url\b/g, '$1_path');
      const unique = [...new Set(rewritten.split(',').map(s => s.trim()))].join(', ');
      return `import { ${unique} } from ${quote}${source}${quote}`;
    });
  }
}
