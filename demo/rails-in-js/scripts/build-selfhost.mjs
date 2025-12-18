#!/usr/bin/env node
// Selfhost build script for Rails-in-JS
// Transpiles Ruby files to JavaScript using the selfhost (JavaScript-based) converter

import { readFile, writeFile, mkdir, rm } from 'fs/promises';
import { join, relative, dirname as pathDirname, resolve } from 'path';
import { exec } from 'child_process';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

export class SelfhostBuilder {
  static DEMO_ROOT = join(__dirname, '..');

  // Shared converter state (initialized once across all instances)
  static converter = null;
  static filters = [];

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

  async transpileFile(srcPath, destPath) {
    const source = await readFile(srcPath, 'utf-8');
    const relativeSrc = relative(SelfhostBuilder.DEMO_ROOT, srcPath);

    const js = SelfhostBuilder.converter.convert(source, {
      eslevel: 2022,
      file: relativeSrc,
      filters: SelfhostBuilder.filters,
      autoexports: true
    });

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

  // Compile ERB template to JavaScript render function code
  compileERBToCode(template, viewName) {
    const ivarPattern = /@(\w+)/g;
    const ivars = new Set();
    let match;
    while ((match = ivarPattern.exec(template)) !== null) {
      ivars.add(match[1]);
    }

    let code = 'export function render(';
    if (ivars.size > 0) {
      code += '{ ' + [...ivars].sort().join(', ') + ' }';
    }
    code += ') {\n';
    code += '  let _buf = "";\n';

    let pos = 0;
    while (pos < template.length) {
      const erbStart = template.indexOf('<%', pos);

      if (erbStart === -1) {
        const text = template.slice(pos);
        if (text) {
          code += '  _buf += ' + JSON.stringify(text) + ';\n';
        }
        break;
      }

      if (erbStart > pos) {
        const text = template.slice(pos, erbStart);
        code += '  _buf += ' + JSON.stringify(text) + ';\n';
      }

      const erbEnd = template.indexOf('%>', erbStart);
      if (erbEnd === -1) {
        throw new Error('Unclosed ERB tag');
      }

      let tag = template.slice(erbStart + 2, erbEnd);

      const trimTrailing = tag.endsWith('-');
      if (trimTrailing) {
        tag = tag.slice(0, -1);
      }

      tag = tag.trim();

      if (tag.startsWith('=')) {
        let expr = tag.slice(1).trim();
        expr = expr.replace(/@(\w+)/g, '$1');
        code += '  _buf += String(' + expr + ');\n';
      } else if (tag.startsWith('-')) {
        let expr = tag.slice(1).trim();
        expr = expr.replace(/@(\w+)/g, '$1');
        code += '  _buf += (' + expr + ');\n';
      } else {
        if (tag.includes('.each')) {
          const eachMatch = tag.match(/(\S+)\.each\s+do\s+\|(\w+)\|/);
          if (eachMatch) {
            let collection = eachMatch[1].replace(/@(\w+)/g, '$1');
            code += '  for (let ' + eachMatch[2] + ' of ' + collection + ') {\n';
          }
        } else if (tag === 'end') {
          code += '  };\n';
        } else if (tag.startsWith('if ')) {
          let cond = tag.slice(3).replace(/@(\w+)/g, '$1');
          code += '  if (' + cond + ') {\n';
        } else if (tag.startsWith('elsif ')) {
          let cond = tag.slice(6).replace(/@(\w+)/g, '$1');
          code += '  } else if (' + cond + ') {\n';
        } else if (tag === 'else') {
          code += '  } else {\n';
        } else if (tag.startsWith('unless ')) {
          let cond = tag.slice(7).replace(/@(\w+)/g, '$1');
          code += '  if (!(' + cond + ')) {\n';
        } else {
          let jsCode = tag.replace(/@(\w+)/g, '$1');
          code += '  ' + jsCode + ';\n';
        }
      }

      pos = erbEnd + 2;
      if (trimTrailing && pos < template.length && template[pos] === '\n') {
        pos++;
      }
    }

    code += '  return _buf\n';
    code += '}\n';

    return code;
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
const isMain = import.meta.url === `file://${process.argv[1]}` ||
               import.meta.url === `file://${resolve(process.argv[1])}`;
if (isMain) {
  const distDir = process.argv[2] ? resolve(process.argv[2]) : undefined;
  const builder = new SelfhostBuilder(distDir);
  builder.build().catch(err => {
    console.error(err);
    process.exit(1);
  });
}
