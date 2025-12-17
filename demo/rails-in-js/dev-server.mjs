#!/usr/bin/env node
// Dev server for Rails-in-JS with hot reload
// Usage: node dev-server.mjs [--selfhost] [--port=3000]

import { createServer } from 'http';
import { readFile, stat } from 'fs/promises';
import { join, extname } from 'path';
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
    // TODO: Implement selfhost transpilation
    // For now, fall back to Ruby with a warning
    console.log('\x1b[33m[selfhost]\x1b[0m Not yet implemented, using Ruby backend');
    await runRubyBuild();
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
