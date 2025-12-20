#!/usr/bin/env node
// Selfhost build script for Rails-in-JS
// Transpiles Ruby files to JavaScript using the selfhost (JavaScript-based) converter

import { readFile, writeFile, mkdir, rm } from 'fs/promises';
import { join, relative, dirname as pathDirname, resolve } from 'path';
import { exec } from 'child_process';
import { fileURLToPath } from 'url';
import { dirname } from 'path';
import { ErbCompiler } from '../../selfhost/lib/erb_compiler.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

export class SelfhostBuilder {
  static DEMO_ROOT = join(__dirname, '..');

  // Shared converter state (initialized once across all instances)
  static converter = null;
  static filters = [];
  static erbFilters = [];  // Separate filter chain for ERB templates
  static ErbCompiler = null;  // Transpiled from lib/erb_compiler.rb

  constructor(distDir) {
    this.distDir = distDir || join(SelfhostBuilder.DEMO_ROOT, 'dist');
  }

  async init() {
    if (SelfhostBuilder.converter) return;

    const selfhostPath = join(SelfhostBuilder.DEMO_ROOT, '../selfhost/ruby2js.js');
    const filtersPath = join(SelfhostBuilder.DEMO_ROOT, '../selfhost/filters');

    const module = await import(selfhostPath);
    await module.initPrism();
    SelfhostBuilder.converter = module;

    // Load core filters
    const { Functions } = await import(join(filtersPath, 'functions.js'));
    const { ESM } = await import(join(filtersPath, 'esm.js'));
    const { Return } = await import(join(filtersPath, 'return.js'));
    const { Erb } = await import(join(filtersPath, 'erb.js'));

    // Load Rails filters
    const { Rails_Model } = await import(join(filtersPath, 'rails/model.js'));
    const { Rails_Controller } = await import(join(filtersPath, 'rails/controller.js'));
    const { Rails_Routes } = await import(join(filtersPath, 'rails/routes.js'));
    const { Rails_Schema } = await import(join(filtersPath, 'rails/schema.js'));
    const { Rails_Logger } = await import(join(filtersPath, 'rails/logger.js'));
    const { Rails_Seeds } = await import(join(filtersPath, 'rails/seeds.js'));

    // Pass .prototype because Pipeline expects objects with methods, not classes
    // IMPORTANT: ESM must come before any filter with on_send (Logger, Functions)
    // to properly convert import/export calls to import/export nodes
    SelfhostBuilder.filters = [
      Rails_Model.prototype,
      Rails_Controller.prototype,
      Rails_Routes.prototype,
      Rails_Schema.prototype,
      Rails_Seeds.prototype,
      ESM.prototype,
      Rails_Logger.prototype,
      Functions.prototype,
      Return.prototype
    ];

    // ERB filter chain: erb handles link_to/form helpers, functions for iterators
    SelfhostBuilder.erbFilters = [
      Erb.prototype,
      Functions.prototype,
      Return.prototype
    ];

    // Use pre-transpiled ErbCompiler (transpiled during selfhost build)
    SelfhostBuilder.ErbCompiler = ErbCompiler;

    console.log('Initialized selfhost with filters: rails/model,controller,routes,schema,seeds, esm, logger, functions, return');
  }

  async findFiles(dir, pattern) {
    return new Promise((resolve) => {
      exec(`find "${dir}" -name "${pattern}" 2>/dev/null`, (err, stdout) => {
        if (err && !stdout) resolve([]);
        else resolve(stdout.trim().split('\n').filter(f => f));
      });
    });
  }

  async transpileFile(srcPath, destPath, generateSourcemap = true) {
    const source = await readFile(srcPath, 'utf-8');
    const relativeSrc = relative(SelfhostBuilder.DEMO_ROOT, srcPath);

    const result = SelfhostBuilder.converter.convert(source, {
      eslevel: 2022,
      file: relativeSrc,
      filters: SelfhostBuilder.filters,
      autoexports: true
    });

    let js = result.toString();

    // Validate JavaScript syntax
    try {
      const dataUrl = `data:text/javascript,${encodeURIComponent(js)}`;
      await import(dataUrl);
    } catch (syntaxErr) {
      const match = syntaxErr.message.match(/^(.+?)(?:\n|$)/);
      const shortErr = match ? match[1] : syntaxErr.message;
      if (!shortErr.includes('Failed to resolve module')) {
        console.error(`\x1b[31m[syntax]\x1b[0m ${relativeSrc}: ${shortErr}`);
      }
    }

    await mkdir(pathDirname(destPath), { recursive: true });

    // Generate sourcemap if requested
    if (generateSourcemap) {
      try {
        const sourcemap = result.sourcemap;  // getter, not a method
        if (sourcemap) {
          const mapPath = destPath + '.map';
          const mapFilename = mapPath.split('/').pop();
          // Add sourcemap reference to JS file
          js += `\n//# sourceMappingURL=${mapFilename}\n`;
          await writeFile(mapPath, JSON.stringify(sourcemap));
        }
      } catch (err) {
        // Sourcemap generation is optional, log but don't fail
        console.error(`\x1b[33m[sourcemap]\x1b[0m ${relativeSrc}: ${err.message}`);
      }
    }

    await writeFile(destPath, js);

    return js;
  }

  async transpileDirectory(srcDir, destDir) {
    let count = 0;
    const files = await this.findFiles(srcDir, '*.rb');

    for (const srcPath of files) {
      const relativePath = relative(srcDir, srcPath);
      const destPath = join(destDir, relativePath.replace(/\.rb$/, '.js'));

      try {
        await this.transpileFile(srcPath, destPath);
        console.log(`  ${relative(SelfhostBuilder.DEMO_ROOT, srcPath)} -> ${relative(SelfhostBuilder.DEMO_ROOT, destPath)}`);
        count++;
      } catch (err) {
        console.error(`\x1b[31m[error]\x1b[0m ${relative(SelfhostBuilder.DEMO_ROOT, srcPath)}: ${err.message}`);
      }
    }

    return count;
  }

  async copyLibFiles() {
    const libSrc = join(SelfhostBuilder.DEMO_ROOT, 'lib');
    const libDest = join(this.distDir, 'lib');
    let count = 0;

    await mkdir(libDest, { recursive: true });
    const files = await this.findFiles(libSrc, '*.js');

    for (const srcPath of files) {
      const content = await readFile(srcPath);
      const destPath = join(libDest, relative(libSrc, srcPath));
      await mkdir(pathDirname(destPath), { recursive: true });
      await writeFile(destPath, content);
      console.log(`  ${relative(SelfhostBuilder.DEMO_ROOT, srcPath)} -> ${relative(SelfhostBuilder.DEMO_ROOT, destPath)}`);
      count++;
    }

    return count;
  }

  async generateModelsIndex() {
    const modelsDir = join(this.distDir, 'models');
    const files = await this.findFiles(modelsDir, '*.js');

    const models = files
      .map(f => f.split('/').pop().replace('.js', ''))
      .filter(name => name !== 'application_record' && name !== 'index')
      .sort();

    if (models.length > 0) {
      const indexJs = models.map(name => {
        const className = name.split('_').map(s => s.charAt(0).toUpperCase() + s.slice(1)).join('');
        return `export { ${className} } from './${name}.js';`;
      }).join('\n') + '\n';

      await writeFile(join(modelsDir, 'index.js'), indexJs);
      console.log(`  -> models/index.js (re-exports: ${models.join(', ')})`);
      return 1;
    }
    return 0;
  }

  // Compile ERB template to Ruby code, then transpile to JavaScript
  // Uses the transpiled ErbCompiler (from lib/erb_compiler.rb) for consistency with Ruby build
  compileERBToCode(template, viewName) {
    // Step 1: Use the transpiled ErbCompiler to generate Ruby code
    const rubyCode = new SelfhostBuilder.ErbCompiler(template).src;

    // Step 2: Transpile Ruby code through selfhost converter with erb filter
    const result = SelfhostBuilder.converter.convert(rubyCode, {
      eslevel: 2022,
      filters: SelfhostBuilder.erbFilters
    });

    // Step 3: Add export keyword (use multiline flag to match after imports)
    return result.toString().replace(/^function render/m, 'export function render');
  }

  async transpileErbDirectory(srcDir, destDir) {
    let count = 0;
    const viewNames = [];

    await mkdir(destDir, { recursive: true });
    const erbOutDir = join(destDir, 'erb');
    await mkdir(erbOutDir, { recursive: true });

    const files = await this.findFiles(srcDir, '*.html.erb');

    for (const srcPath of files) {
      const basename = srcPath.split('/').pop().replace('.html.erb', '');
      viewNames.push(basename);

      try {
        const template = await readFile(srcPath, 'utf-8');
        const js = this.compileERBToCode(template, basename);
        const destPath = join(erbOutDir, `${basename}.js`);
        await writeFile(destPath, js);
        console.log(`  ${relative(SelfhostBuilder.DEMO_ROOT, srcPath)} -> ${relative(SelfhostBuilder.DEMO_ROOT, destPath)}`);
        count++;
      } catch (err) {
        console.error(`\x1b[31m[erb]\x1b[0m ${basename}.html.erb: ${err.message}`);
      }
    }

    if (viewNames.length > 0) {
      viewNames.sort();
      let articlesJs = `// Article views - auto-generated from .html.erb templates
// Each exported function is a render function that takes { article } or { articles }

`;
      for (const name of viewNames) {
        articlesJs += `import { render as ${name}_render } from './erb/${name}.js';\n`;
      }

      articlesJs += `
// Export ArticleViews - method names match controller action names
export const ArticleViews = {
`;
      for (const name of viewNames) {
        articlesJs += `  ${name}: ${name}_render,\n`;
      }
      articlesJs += `  // $new alias for 'new' (JS reserved word handling)
  $new: new_render
};
`;

      await writeFile(join(destDir, 'articles.js'), articlesJs);
      console.log(`  -> views/articles.js (combined ERB module)`);
      count++;
    }

    return count;
  }

  async build() {
    const startTime = Date.now();
    console.log('=== Building Rails-in-JS (selfhost) ===\n');

    await this.init();
    console.log();

    // Clean dist directory
    await rm(this.distDir, { recursive: true, force: true });
    await mkdir(this.distDir, { recursive: true });

    let totalFiles = 0;

    console.log('Library:');
    totalFiles += await this.copyLibFiles();
    console.log();

    console.log('Models:');
    totalFiles += await this.transpileDirectory(
      join(SelfhostBuilder.DEMO_ROOT, 'app/models'),
      join(this.distDir, 'models')
    );
    totalFiles += await this.generateModelsIndex();
    console.log();

    console.log('Controllers:');
    totalFiles += await this.transpileDirectory(
      join(SelfhostBuilder.DEMO_ROOT, 'app/controllers'),
      join(this.distDir, 'controllers')
    );
    console.log();

    console.log('Helpers:');
    totalFiles += await this.transpileDirectory(
      join(SelfhostBuilder.DEMO_ROOT, 'app/helpers'),
      join(this.distDir, 'helpers')
    );
    console.log();

    console.log('Config:');
    totalFiles += await this.transpileDirectory(
      join(SelfhostBuilder.DEMO_ROOT, 'config'),
      join(this.distDir, 'config')
    );
    console.log();

    console.log('Database:');
    totalFiles += await this.transpileDirectory(
      join(SelfhostBuilder.DEMO_ROOT, 'db'),
      join(this.distDir, 'db')
    );
    console.log();

    console.log('Views:');
    totalFiles += await this.transpileErbDirectory(
      join(SelfhostBuilder.DEMO_ROOT, 'app/views/articles'),
      join(this.distDir, 'views')
    );
    console.log();

    const elapsed = Date.now() - startTime;
    console.log(`=== Build Complete: ${totalFiles} files in ${elapsed}ms ===`);

    return totalFiles;
  }
}

// CLI entry point
const isMain = process.argv[1] && (
  import.meta.url === `file://${process.argv[1]}` ||
  import.meta.url === `file://${resolve(process.argv[1])}`
);
if (isMain) {
  const distDir = process.argv[2] ? resolve(process.argv[2]) : undefined;
  const builder = new SelfhostBuilder(distDir);
  builder.build().catch(err => {
    console.error(err);
    process.exit(1);
  });
}
