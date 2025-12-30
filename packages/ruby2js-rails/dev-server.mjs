#!/usr/bin/env node
// Dev server for Ruby2JS-on-Rails with hot reload
// Usage: node dev-server.mjs [--ruby] [--port=3000]

import { createServer } from 'http';
import { readFile, stat, access } from 'fs/promises';
import { join, extname } from 'path';
import { watch } from 'chokidar';
import { WebSocketServer } from 'ws';
import { exec } from 'child_process';
// SelfhostBuilder is dynamically imported only when needed (not with --ruby flag)

// Parse command line arguments
const args = process.argv.slice(2);
const useRuby = args.includes('--ruby');
const portArg = args.find(a => a.startsWith('--port='));
const PORT = portArg ? parseInt(portArg.split('=')[1]) : 3000;
const appRootArg = args.find(a => a.startsWith('--app-root='));

// App root - use --app-root if provided, otherwise current working directory
const APP_ROOT = appRootArg ? appRootArg.split('=')[1] : process.cwd();

// Detect CSS framework
let cssFramework = 'none';
let tailwindType = null; // 'rails' or 'standalone'
async function detectCssFramework() {
  // Check for tailwindcss-rails (app/assets/tailwind/application.css)
  try {
    await access(join(APP_ROOT, 'app/assets/tailwind/application.css'));
    cssFramework = 'tailwind';
    tailwindType = 'rails';
    console.log('\x1b[36m[css]\x1b[0m Tailwind CSS detected (tailwindcss-rails)');
    return;
  } catch {}

  // Check for standalone Tailwind (tailwind.config.js)
  try {
    await access(join(APP_ROOT, 'tailwind.config.js'));
    cssFramework = 'tailwind';
    tailwindType = 'standalone';
    console.log('\x1b[36m[css]\x1b[0m Tailwind CSS detected (standalone)');
    return;
  } catch {}

  try {
    const pkg = JSON.parse(await readFile(join(APP_ROOT, 'package.json'), 'utf8'));
    if (pkg.dependencies?.['@picocss/pico']) {
      cssFramework = 'pico';
      console.log('\x1b[36m[css]\x1b[0m Pico CSS detected');
    }
  } catch {}
}

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

// Selfhost builder instance (reused across builds)
let builder = null;

// Transpilation backend
async function runBuild() {
  if (building) {
    buildPending = true;
    return;
  }

  building = true;
  const startTime = Date.now();

  if (useRuby) {
    console.log('\x1b[33m[ruby]\x1b[0m Transpiling with Ruby...');
    await runRubyBuild();
  } else {
    await runSelfhostBuild();
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
    exec("ruby -r ruby2js/rails/builder -e 'SelfhostBuilder.new.build'", { cwd: APP_ROOT }, (error, stdout, stderr) => {
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

async function runSelfhostBuild() {
  try {
    // Dynamically import SelfhostBuilder only when needed
    // This avoids loading selfhost dependencies when using --ruby flag
    if (!builder) {
      const { SelfhostBuilder } = await import('./build.mjs');
      builder = new SelfhostBuilder(join(APP_ROOT, 'dist'), APP_ROOT);
    }
    await builder.build();
  } catch (err) {
    console.error('\x1b[31m[build]\x1b[0m Build failed:', err.message);
    console.log('\x1b[33m[build]\x1b[0m Falling back to Ruby backend');
    return runRubyBuild();
  }
}

// CSS build state
let cssBuildPending = false;
let cssBuildRunning = false;

async function runCssBuild() {
  if (cssFramework !== 'tailwind') return;

  if (cssBuildRunning) {
    cssBuildPending = true;
    return;
  }

  cssBuildRunning = true;
  const startTime = Date.now();
  console.log('\x1b[35m[css]\x1b[0m Building Tailwind CSS...');

  // Use appropriate command based on Tailwind setup
  // Run from dist/ directory where tailwindcss is installed
  const distDir = join(APP_ROOT, 'dist');
  const buildCmd = tailwindType === 'rails'
    ? 'npx tailwindcss -i app/assets/tailwind/application.css -o app/assets/builds/tailwind.css'
    : 'npx tailwindcss -i ./src/input.css -o ./public/styles.css';

  try {
    await new Promise((resolve, reject) => {
      exec(buildCmd, { cwd: distDir }, (error, stdout, stderr) => {
        if (error) {
          console.error('\x1b[31m[css error]\x1b[0m', error.message);
          if (stderr) console.error(stderr);
          resolve(); // Don't reject - continue watching
        } else {
          const elapsed = Date.now() - startTime;
          console.log(`\x1b[35m[css]\x1b[0m Built in ${elapsed}ms`);
          resolve();
        }
      });
    });
    notifyClients();
  } finally {
    cssBuildRunning = false;
    if (cssBuildPending) {
      cssBuildPending = false;
      runCssBuild();
    }
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

  const filePath = join(APP_ROOT, url);
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
          const indexContent = await readFile(join(APP_ROOT, 'index.html'));
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
  join(APP_ROOT, 'app'),
  join(APP_ROOT, 'config'),
  join(APP_ROOT, 'db'),
  join(APP_ROOT, 'src')  // For Tailwind CSS input
];

const watcher = watch(watchPaths, {
  ignored: /node_modules|\.git|dist|public/,
  persistent: true,
  ignoreInitial: true
});

// Debounce timers for different build types
let rubyDebounceTimer = null;
let cssDebounceTimer = null;

function onFileChange(event, path) {
  const relativePath = path.replace(APP_ROOT + '/', '');

  // Handle CSS files
  if (path.endsWith('.css') && !path.includes('public/') && !path.includes('builds/')) {
    console.log(`\x1b[35m[${event}]\x1b[0m ${relativePath}`);
    if (cssDebounceTimer) clearTimeout(cssDebounceTimer);
    cssDebounceTimer = setTimeout(() => {
      cssDebounceTimer = null;
      runCssBuild();
    }, 100);
    return;
  }

  // Handle Ruby/ERB files
  if (!path.endsWith('.rb') && !path.endsWith('.erb')) return;

  console.log(`\x1b[33m[${event}]\x1b[0m ${relativePath}`);

  // Debounce rapid changes
  if (rubyDebounceTimer) clearTimeout(rubyDebounceTimer);
  rubyDebounceTimer = setTimeout(() => {
    rubyDebounceTimer = null;
    runBuild();
    // Also rebuild Tailwind CSS when views change (JIT needs to scan for new classes)
    if (cssFramework === 'tailwind' && path.includes('/views/')) {
      runCssBuild();
    }
  }, 100);
}

watcher.on('change', (path) => onFileChange('change', path));
watcher.on('add', (path) => onFileChange('add', path));
watcher.on('unlink', (path) => onFileChange('unlink', path));

// Start server
server.listen(PORT, async () => {
  console.log('');
  console.log('\x1b[1m=== Ruby2JS-on-Rails Dev Server ===\x1b[0m');
  console.log('');

  // Detect CSS framework
  await detectCssFramework();

  console.log(`  \x1b[32m➜\x1b[0m  Local:   http://localhost:${PORT}/`);
  console.log(`  \x1b[36m➜\x1b[0m  Mode:    ${useRuby ? 'Ruby transpilation' : 'JavaScript (selfhost)'}`);
  if (cssFramework !== 'none') {
    console.log(`  \x1b[35m➜\x1b[0m  CSS:     ${cssFramework}`);
  }
  console.log('');
  console.log('Watching for changes in app/, config/, db/' + (cssFramework === 'tailwind' ? ', src/' : ''));
  console.log('Press Ctrl+C to stop');
  console.log('');

  // Run initial builds
  runBuild();
  if (cssFramework === 'tailwind') {
    runCssBuild();
  }
});

// Graceful shutdown
process.on('SIGINT', () => {
  console.log('\n\x1b[33m[shutdown]\x1b[0m Stopping server...');
  watcher.close();
  wss.close();
  server.close();
  process.exit(0);
});
