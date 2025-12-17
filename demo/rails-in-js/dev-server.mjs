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

  const selfhostPath = join(__dirname, '../selfhost/ruby2js.mjs');
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
    selfhostFilters = [
      // Rails filters first (they transform high-level patterns)
      Rails_Model.prototype,
      Rails_Controller.prototype,
      Rails_Routes.prototype,
      Rails_Schema.prototype,
      Rails_Logger.prototype,
      Rails_Seeds.prototype,
      // Then core filters
      Functions.prototype,
      ESM.prototype,
      Return.prototype
    ];

    console.log('\x1b[32m[selfhost]\x1b[0m Initialized with filters: rails/*, functions, esm, return');
  } catch (err) {
    console.error('\x1b[31m[selfhost]\x1b[0m Failed to initialize:', err.message);
    throw err;
  }
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
        const js = selfhostConverter.convert(source, {
          eslevel: 2022,
          file: relative(__dirname, srcPath),
          filters: selfhostFilters,
          autoexports: true,
          autoimports: {
            ApplicationRecord: './application_record.js',
            ApplicationController: './application_controller.js'
          }
        });

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
