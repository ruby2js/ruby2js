#!/usr/bin/env node
//
// Local development server for the WebContainers editor.
//
// Usage:
//   node editor/serve.mjs [demo/blog] [--port 8080] [--skip-snapshot]
//
// This script:
//   1. Builds a JSON snapshot via editor/snapshot.mjs
//   2. Serves editor/ with COOP/COEP headers required by WebContainers
//
// Prerequisites:
//   - A demo directory must exist (e.g. demo/blog, artifacts/blog)
//   - For tarballs install: artifacts/tarballs/ (from: bundle exec rake -f demo/selfhost/Rakefile release)

import { createServer } from 'node:http';
import { readFileSync, existsSync, statSync } from 'node:fs';
import { join, extname, resolve } from 'node:path';
import { execSync } from 'node:child_process';
import { parseArgs } from 'node:util';

const ROOT = resolve(import.meta.dirname, '..');
const EDITOR_DIR = join(ROOT, 'editor');

const { values: opts, positionals } = parseArgs({
  options: {
    port: { type: 'string', default: '8080' },
    'skip-snapshot': { type: 'boolean', default: false },
  },
  allowPositionals: true,
});

const srcDir = positionals[0] || 'demo/blog';
const demo = srcDir.split('/').pop();
const port = parseInt(opts.port);
const snapshotPath = join(EDITOR_DIR, 'snapshots', `${demo}.json`);

// Step 1: Build snapshot
if (!opts['skip-snapshot']) {
  console.log(`Building snapshot from ${srcDir}...`);
  execSync(`node editor/snapshot.mjs "${srcDir}"`, { cwd: ROOT, stdio: 'inherit' });
} else {
  if (!existsSync(snapshotPath)) {
    console.error(`Error: ${snapshotPath} does not exist. Run without --skip-snapshot first.`);
    process.exit(1);
  }
  console.log('Using existing snapshot.');
}

// Step 2: Serve with COOP/COEP headers
const MIME = {
  '.html': 'text/html',
  '.js': 'text/javascript',
  '.mjs': 'text/javascript',
  '.css': 'text/css',
  '.json': 'application/json',
  '.ico': 'image/x-icon',
};

const server = createServer((req, res) => {
  res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
  res.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
  res.setHeader('Cache-Control', 'no-cache');

  let urlPath = new URL(req.url, `http://localhost:${port}`).pathname;

  // Map /ruby2js/editor/ paths to editor/ directory (match deployed structure)
  if (urlPath.startsWith('/ruby2js/editor/')) {
    urlPath = urlPath.slice('/ruby2js/editor'.length);
  }

  if (urlPath === '/' || urlPath === '') urlPath = '/index.html';

  const filePath = join(EDITOR_DIR, urlPath);

  if (!existsSync(filePath) || !statSync(filePath).isFile()) {
    res.writeHead(404);
    res.end('Not found');
    return;
  }

  const ext = extname(filePath);
  const mime = MIME[ext] || 'application/octet-stream';
  res.setHeader('Content-Type', mime);
  res.end(readFileSync(filePath));
});

server.listen(port, () => {
  console.log(`\nEditor: http://localhost:${port}/?demo=${demo}`);
  console.log('COOP/COEP headers enabled for WebContainers.\n');
});
