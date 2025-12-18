#!/usr/bin/env node
// Selfhost build script for Rails-in-JS
// Transpiles Ruby files to JavaScript using the selfhost (JavaScript-based) converter

import { readFile, writeFile, mkdir, rm } from 'fs/promises';
import { join, relative, dirname as pathDirname } from 'path';
import { exec } from 'child_process';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const DEMO_ROOT = join(__dirname, '..');
const DIST_DIR = join(DEMO_ROOT, 'dist');

// Selfhost converter and filters
let selfhostConverter = null;
let selfhostFilters = [];

async function initSelfhost() {
  if (selfhostConverter) return;

  const selfhostPath = join(DEMO_ROOT, '../selfhost/ruby2js.js');
  const filtersPath = join(DEMO_ROOT, '../selfhost/filters');

  const module = await import(selfhostPath);
  await module.initPrism();
  selfhostConverter = module;

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
  selfhostFilters = [
    // Rails filters that add imports/exports (as send nodes)
    Rails_Model.prototype,
    Rails_Controller.prototype,
    Rails_Routes.prototype,
    Rails_Schema.prototype,
    Rails_Seeds.prototype,
    // ESM converts import/export sends to proper nodes - must be before on_send filters
    ESM.prototype,
    // Filters with on_send handlers
    Rails_Logger.prototype,
    Functions.prototype,
    // Other filters
    Return.prototype
  ];

  console.log('Initialized selfhost with filters: rails/model,controller,routes,schema,seeds, esm, logger, functions, return');
}

async function findFiles(dir, pattern) {
  return new Promise((resolve) => {
    exec(`find "${dir}" -name "${pattern}" 2>/dev/null`, (err, stdout) => {
      if (err && !stdout) resolve([]);
      else resolve(stdout.trim().split('\n').filter(f => f));
    });
  });
}

async function transpileFile(srcPath, destPath) {
  const source = await readFile(srcPath, 'utf-8');
  const relativeSrc = relative(DEMO_ROOT, srcPath);

  // Transpile with selfhost
  const js = selfhostConverter.convert(source, {
    eslevel: 2022,
    file: relativeSrc,
    filters: selfhostFilters,
    autoexports: true
  });

  // Validate JavaScript syntax
  try {
    const dataUrl = `data:text/javascript,${encodeURIComponent(js)}`;
    await import(dataUrl);
  } catch (syntaxErr) {
    const match = syntaxErr.message.match(/^(.+?)(?:\n|$)/);
    const shortErr = match ? match[1] : syntaxErr.message;
    // Only report actual syntax errors, not import resolution errors
    if (!shortErr.includes('Failed to resolve module')) {
      console.error(`\x1b[31m[syntax]\x1b[0m ${relativeSrc}: ${shortErr}`);
    }
  }

  await mkdir(pathDirname(destPath), { recursive: true });
  await writeFile(destPath, js);

  return js;
}

async function transpileDirectory(srcDir, destDir) {
  let count = 0;
  const files = await findFiles(srcDir, '*.rb');

  for (const srcPath of files) {
    const relativePath = relative(srcDir, srcPath);
    const destPath = join(destDir, relativePath.replace(/\.rb$/, '.js'));

    try {
      await transpileFile(srcPath, destPath);
      console.log(`  ${relative(DEMO_ROOT, srcPath)} -> ${relative(DEMO_ROOT, destPath)}`);
      count++;
    } catch (err) {
      console.error(`\x1b[31m[error]\x1b[0m ${relative(DEMO_ROOT, srcPath)}: ${err.message}`);
    }
  }

  return count;
}

async function copyLibFiles() {
  const libSrc = join(DEMO_ROOT, 'lib');
  const libDest = join(DIST_DIR, 'lib');
  let count = 0;

  await mkdir(libDest, { recursive: true });
  const files = await findFiles(libSrc, '*.js');

  for (const srcPath of files) {
    const content = await readFile(srcPath);
    const destPath = join(libDest, relative(libSrc, srcPath));
    await mkdir(pathDirname(destPath), { recursive: true });
    await writeFile(destPath, content);
    console.log(`  ${relative(DEMO_ROOT, srcPath)} -> ${relative(DEMO_ROOT, destPath)}`);
    count++;
  }

  return count;
}

async function generateModelsIndex() {
  const modelsDir = join(DIST_DIR, 'models');
  const files = await findFiles(modelsDir, '*.js');

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

async function main() {
  const startTime = Date.now();
  console.log('=== Building Rails-in-JS (selfhost) ===\n');

  try {
    await initSelfhost();
  } catch (err) {
    console.error(`\x1b[31m[error]\x1b[0m Failed to initialize selfhost: ${err.message}`);
    process.exit(1);
  }

  console.log();

  // Clean dist directory
  await rm(DIST_DIR, { recursive: true, force: true });
  await mkdir(DIST_DIR, { recursive: true });

  let totalFiles = 0;

  // Copy lib files
  console.log('Library:');
  totalFiles += await copyLibFiles();
  console.log();

  // Transpile models
  console.log('Models:');
  totalFiles += await transpileDirectory(
    join(DEMO_ROOT, 'app/models'),
    join(DIST_DIR, 'models')
  );
  totalFiles += await generateModelsIndex();
  console.log();

  // Transpile controllers
  console.log('Controllers:');
  totalFiles += await transpileDirectory(
    join(DEMO_ROOT, 'app/controllers'),
    join(DIST_DIR, 'controllers')
  );
  console.log();

  // Transpile helpers
  console.log('Helpers:');
  totalFiles += await transpileDirectory(
    join(DEMO_ROOT, 'app/helpers'),
    join(DIST_DIR, 'helpers')
  );
  console.log();

  // Transpile config
  console.log('Config:');
  totalFiles += await transpileDirectory(
    join(DEMO_ROOT, 'config'),
    join(DIST_DIR, 'config')
  );
  console.log();

  // Transpile db (seeds)
  console.log('Database:');
  totalFiles += await transpileDirectory(
    join(DEMO_ROOT, 'db'),
    join(DIST_DIR, 'db')
  );
  console.log();

  const elapsed = Date.now() - startTime;
  console.log(`=== Build Complete: ${totalFiles} files in ${elapsed}ms ===`);
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
