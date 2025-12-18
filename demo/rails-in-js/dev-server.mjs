#!/usr/bin/env node
// Dev server for Rails-in-JS with hot reload
// Usage: node dev-server.mjs [--selfhost] [--port=3000]

import { createServer } from 'http';
import { readFile, stat, writeFile, mkdir } from 'fs/promises';
import { join, extname, relative, dirname as pathDirname } from 'path';
import { watch } from 'chokidar';
import { WebSocketServer } from 'ws';
import { exec } from 'child_process';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Parse command line arguments
const args = process.argv.slice(2);
const selfhost = args.includes('--selfhost');
const portArg = args.find(a => a.startsWith('--port='));
const PORT = portArg ? parseInt(portArg.split('=')[1]) : 3000;

// MIME types for static file serving
const MIME_TYPES = {
  '.html': 'text/html',
  '.js': 'text/javascript',
  '.mjs': 'text/javascript',
  '.css': 'text/css',
  '.json': 'application/json',
  '.wasm': 'application/wasm',
  '.ico': 'image/x-icon',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.rb': 'text/plain',
  '.erb': 'text/plain',
  '.map': 'application/json'
};

// Track connected WebSocket clients
const clients = new Set();

// Build state
let building = false;
let buildPending = false;

// Transpilation backend
async function runBuild() {
  if (building) {
    buildPending = true;
    return;
  }

  building = true;
  const startTime = Date.now();

  if (selfhost) {
    console.log('\x1b[33m[selfhost]\x1b[0m Transpiling with JavaScript...');
    await runSelfhostBuild();
  } else {
    await runRubyBuild();
  }

  const elapsed = Date.now() - startTime;
  console.log(`\x1b[32m[build]\x1b[0m Done in ${elapsed}ms`);

  // Notify all connected browsers to reload
  notifyClients();

  building = false;

  // If another build was requested while we were building, run it now
  if (buildPending) {
    buildPending = false;
    runBuild();
  }
}

function runRubyBuild() {
  return new Promise((resolve, reject) => {
    exec('ruby scripts/build.rb', { cwd: __dirname }, (error, stdout, stderr) => {
      if (error) {
        console.error('\x1b[31m[build error]\x1b[0m', error.message);
        if (stderr) console.error(stderr);
        resolve(); // Don't reject - we still want to continue watching
      } else {
        // Show abbreviated output
        const lines = stdout.trim().split('\n');
        const fileCount = lines.filter(l => l.includes('->')).length;
        console.log(`\x1b[32m[build]\x1b[0m Transpiled ${fileCount} files`);
        resolve();
      }
    });
  });
}

// Selfhost build using JavaScript-based transpilation
let selfhostConverter = null;
let selfhostFilters = [];

async function initSelfhost() {
  if (selfhostConverter) return;

  const selfhostPath = join(__dirname, '../selfhost/ruby2js.js');
  const filtersPath = join(__dirname, '../selfhost/filters');

  try {
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

    console.log('\x1b[32m[selfhost]\x1b[0m Initialized with filters: rails/model,controller,routes,schema,seeds, esm, logger, functions, return');
  } catch (err) {
    console.error('\x1b[31m[selfhost]\x1b[0m Failed to initialize:', err.message);
    throw err;
  }
}

// Compile ERB template to JavaScript render function code
// This is a build-time version of erb_runtime.mjs's compileERB
function compileERBToCode(template, viewName) {
  // Collect instance variables used (for function signature)
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
      // No more ERB tags, add remaining text
      const text = template.slice(pos);
      if (text) {
        code += '  _buf += ' + JSON.stringify(text) + ';\n';
      }
      break;
    }

    // Add text before ERB tag
    if (erbStart > pos) {
      const text = template.slice(pos, erbStart);
      code += '  _buf += ' + JSON.stringify(text) + ';\n';
    }

    // Find end of ERB tag
    const erbEnd = template.indexOf('%>', erbStart);
    if (erbEnd === -1) {
      throw new Error('Unclosed ERB tag');
    }

    let tag = template.slice(erbStart + 2, erbEnd);

    // Handle -%> (trim trailing newline)
    const trimTrailing = tag.endsWith('-');
    if (trimTrailing) {
      tag = tag.slice(0, -1);
    }

    tag = tag.trim();

    if (tag.startsWith('=')) {
      // Output expression: <%= expr %>
      let expr = tag.slice(1).trim();
      // Convert @ivar to ivar
      expr = expr.replace(/@(\w+)/g, '$1');
      code += '  _buf += String(' + expr + ');\n';
    } else if (tag.startsWith('-')) {
      // Unescaped output: <%- expr %>
      let expr = tag.slice(1).trim();
      expr = expr.replace(/@(\w+)/g, '$1');
      code += '  _buf += (' + expr + ');\n';
    } else {
      // Code block: <% code %>
      // Convert Ruby to JS
      if (tag.includes('.each')) {
        // Convert Ruby each to JS for-of
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
        // Other code - convert @ivar to ivar
        let jsCode = tag.replace(/@(\w+)/g, '$1');
        code += '  ' + jsCode + ';\n';
      }
    }

    pos = erbEnd + 2;
    // Handle -%> trimming
    if (trimTrailing && pos < template.length && template[pos] === '\n') {
      pos++;
    }
  }

  code += '  return _buf\n';
  code += '}\n';

  return code;
}

async function runSelfhostBuild() {
  try {
    await initSelfhost();
  } catch {
    console.log('\x1b[33m[selfhost]\x1b[0m Falling back to Ruby backend');
    return runRubyBuild();
  }

  const distDir = join(__dirname, 'dist');
  let fileCount = 0;
  let errorCount = 0;

  // Define source directories and their output mappings
  const sources = [
    { src: 'app/models', dest: 'models' },
    { src: 'app/controllers', dest: 'controllers' },
    { src: 'app/helpers', dest: 'helpers' },
    { src: 'config', dest: 'config' },
    { src: 'db', dest: 'db' }
  ];

  for (const { src, dest } of sources) {
    const srcDir = join(__dirname, src);
    const destDir = join(distDir, dest);

    try {
      await mkdir(destDir, { recursive: true });
    } catch {}

    // Find all .rb files
    const pattern = join(srcDir, '**/*.rb');
    let files;
    try {
      // Use exec to find files since glob may not be available
      files = await new Promise((resolve, reject) => {
        exec(`find "${srcDir}" -name "*.rb" 2>/dev/null`, (err, stdout) => {
          if (err && !stdout) resolve([]);
          else resolve(stdout.trim().split('\n').filter(f => f));
        });
      });
    } catch {
      files = [];
    }

    for (const srcPath of files) {
      const relativePath = relative(srcDir, srcPath);
      const destPath = join(destDir, relativePath.replace(/\.rb$/, '.js'));

      try {
        const source = await readFile(srcPath, 'utf-8');

        // Transpile with selfhost
        // Note: Don't use autoimports - the Rails filters handle imports properly
        // Autoimports can cause duplicate/circular imports
        const js = selfhostConverter.convert(source, {
          eslevel: 2022,
          file: relative(__dirname, srcPath),
          filters: selfhostFilters,
          autoexports: true
        });

        // Validate JavaScript syntax before writing
        try {
          // Use dynamic import to validate ES module syntax
          const dataUrl = `data:text/javascript,${encodeURIComponent(js)}`;
          await import(dataUrl);
        } catch (syntaxErr) {
          // Extract just the syntax error, not the data URL noise
          const match = syntaxErr.message.match(/^(.+?)(?:\n|$)/);
          const shortErr = match ? match[1] : syntaxErr.message;
          console.error(`\x1b[31m[syntax]\x1b[0m ${relative(__dirname, srcPath)}: ${shortErr}`);
          // Still write the file so we can inspect it
        }

        // Ensure destination directory exists
        await mkdir(pathDirname(destPath), { recursive: true });
        await writeFile(destPath, js);
        fileCount++;
      } catch (err) {
        errorCount++;
        console.error(`\x1b[31m[error]\x1b[0m ${relative(__dirname, srcPath)}: ${err.message}`);
      }
    }
  }

  // Copy lib files (these are pure JS, no transpilation needed)
  const libSrc = join(__dirname, 'lib');
  const libDest = join(distDir, 'lib');
  try {
    await mkdir(libDest, { recursive: true });
    const libFiles = await new Promise((resolve, reject) => {
      exec(`find "${libSrc}" -name "*.js" 2>/dev/null`, (err, stdout) => {
        if (err && !stdout) resolve([]);
        else resolve(stdout.trim().split('\n').filter(f => f));
      });
    });
    for (const f of libFiles) {
      const content = await readFile(f);
      await writeFile(join(libDest, relative(libSrc, f)), content);
      fileCount++;
    }
  } catch {}

  // Generate models/index.js that re-exports all models
  const modelsDir = join(distDir, 'models');
  try {
    const modelFiles = await new Promise((resolve) => {
      exec(`find "${modelsDir}" -maxdepth 1 -name "*.js" 2>/dev/null`, (err, stdout) => {
        if (err && !stdout) resolve([]);
        else resolve(stdout.trim().split('\n').filter(f => f));
      });
    });

    const models = modelFiles
      .map(f => f.split('/').pop().replace('.js', ''))
      .filter(name => name !== 'application_record' && name !== 'index')
      .sort();

    if (models.length > 0) {
      const indexJs = models.map(name => {
        const className = name.split('_').map(s => s.charAt(0).toUpperCase() + s.slice(1)).join('');
        return `export { ${className} } from './${name}.js';`;
      }).join('\n') + '\n';

      await writeFile(join(modelsDir, 'index.js'), indexJs);
      fileCount++;
    }
  } catch {}

  // Generate views from ERB templates
  const erbDir = join(__dirname, 'app/views/articles');
  const viewsDir = join(distDir, 'views');
  const erbOutDir = join(viewsDir, 'erb');

  try {
    await mkdir(erbOutDir, { recursive: true });

    // Find all ERB files
    const erbFiles = await new Promise((resolve) => {
      exec(`find "${erbDir}" -name "*.html.erb" 2>/dev/null`, (err, stdout) => {
        if (err && !stdout) resolve([]);
        else resolve(stdout.trim().split('\n').filter(f => f));
      });
    });

    const viewNames = [];

    for (const erbPath of erbFiles) {
      const basename = erbPath.split('/').pop().replace('.html.erb', '');
      viewNames.push(basename);

      try {
        const template = await readFile(erbPath, 'utf-8');
        const js = compileERBToCode(template, basename);
        const destPath = join(erbOutDir, `${basename}.js`);
        await writeFile(destPath, js);
        fileCount++;
      } catch (err) {
        errorCount++;
        console.error(`\x1b[31m[erb]\x1b[0m ${basename}.html.erb: ${err.message}`);
      }
    }

    // Generate combined views/articles.js module
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

      await writeFile(join(viewsDir, 'articles.js'), articlesJs);
      fileCount++;
    }
  } catch (err) {
    console.error(`\x1b[31m[erb]\x1b[0m Failed to process views: ${err.message}`);
  }

  console.log(`\x1b[32m[selfhost]\x1b[0m Transpiled ${fileCount} files` +
    (errorCount > 0 ? ` (\x1b[31m${errorCount} errors\x1b[0m)` : ''));

  if (errorCount > 0) {
    console.log('\x1b[33m[selfhost]\x1b[0m Some files failed to transpile');
    console.log('\x1b[33m[selfhost]\x1b[0m Run without --selfhost if Ruby backend produces better results');
  }
}

function notifyClients() {
  const message = JSON.stringify({ type: 'reload' });
  for (const client of clients) {
    if (client.readyState === 1) { // WebSocket.OPEN
      client.send(message);
    }
  }
  if (clients.size > 0) {
    console.log(`\x1b[36m[reload]\x1b[0m Notified ${clients.size} browser(s)`);
  }
}

// Static file server
async function serveFile(req, res) {
  let url = req.url.split('?')[0]; // Remove query string

  // Default to index.html
  if (url === '/') url = '/index.html';

  // Security: prevent directory traversal
  if (url.includes('..')) {
    res.writeHead(403);
    res.end('Forbidden');
    return;
  }

  const filePath = join(__dirname, url);
  const ext = extname(filePath);
  const contentType = MIME_TYPES[ext] || 'application/octet-stream';

  try {
    const stats = await stat(filePath);
    if (stats.isDirectory()) {
      // Try index.html in directory
      const indexPath = join(filePath, 'index.html');
      const content = await readFile(indexPath);
      res.writeHead(200, { 'Content-Type': 'text/html' });
      res.end(content);
    } else {
      const content = await readFile(filePath);
      res.writeHead(200, { 'Content-Type': contentType });
      res.end(content);
    }
  } catch (err) {
    if (err.code === 'ENOENT') {
      // SPA fallback: if no file extension, serve index.html for client-side routing
      if (!ext || ext === '') {
        try {
          const indexContent = await readFile(join(__dirname, 'index.html'));
          res.writeHead(200, { 'Content-Type': 'text/html' });
          res.end(indexContent);
          return;
        } catch {
          // Fall through to 404
        }
      }
      res.writeHead(404);
      res.end('Not Found: ' + url);
    } else {
      res.writeHead(500);
      res.end('Server Error');
      console.error(err);
    }
  }
}

// Create HTTP server
const server = createServer(serveFile);

// Create WebSocket server on same port
const wss = new WebSocketServer({ server });

wss.on('connection', (ws) => {
  clients.add(ws);
  console.log(`\x1b[36m[ws]\x1b[0m Browser connected (${clients.size} total)`);

  ws.on('close', () => {
    clients.delete(ws);
    console.log(`\x1b[36m[ws]\x1b[0m Browser disconnected (${clients.size} total)`);
  });
});

// File watcher
const watchPaths = [
  join(__dirname, 'app'),
  join(__dirname, 'config'),
  join(__dirname, 'db')
];

const watcher = watch(watchPaths, {
  ignored: /node_modules|\.git|dist/,
  persistent: true,
  ignoreInitial: true
});

// Debounce file changes
let debounceTimer = null;
function onFileChange(event, path) {
  // Only watch .rb and .erb files
  if (!path.endsWith('.rb') && !path.endsWith('.erb')) return;

  const relativePath = path.replace(__dirname + '/', '');
  console.log(`\x1b[33m[${event}]\x1b[0m ${relativePath}`);

  // Debounce rapid changes
  if (debounceTimer) clearTimeout(debounceTimer);
  debounceTimer = setTimeout(() => {
    debounceTimer = null;
    runBuild();
  }, 100);
}

watcher.on('change', (path) => onFileChange('change', path));
watcher.on('add', (path) => onFileChange('add', path));
watcher.on('unlink', (path) => onFileChange('unlink', path));

// Start server
server.listen(PORT, () => {
  console.log('');
  console.log('\x1b[1m=== Rails-in-JS Dev Server ===\x1b[0m');
  console.log('');
  console.log(`  \x1b[32m➜\x1b[0m  Local:   http://localhost:${PORT}/`);
  console.log(`  \x1b[36m➜\x1b[0m  Mode:    ${selfhost ? 'selfhost (experimental)' : 'Ruby transpilation'}`);
  console.log('');
  console.log('Watching for changes in app/, config/, db/');
  console.log('Press Ctrl+C to stop');
  console.log('');

  // Run initial build
  runBuild();
});

// Graceful shutdown
process.on('SIGINT', () => {
  console.log('\n\x1b[33m[shutdown]\x1b[0m Stopping server...');
  watcher.close();
  wss.close();
  server.close();
  process.exit(0);
});
