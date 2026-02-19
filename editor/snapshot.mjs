#!/usr/bin/env node
//
// Build a WebContainer-ready snapshot from a Rails-like demo directory.
//
// Usage:
//   node editor/snapshot.mjs demo/blog
//   node editor/snapshot.mjs demo/blog --output editor/snapshots/blog.json
//
// This script:
//   1. Runs `juntos init` if needed (adds package.json, vite.config.js, etc.)
//   2. Runs `npm install` if needed (with cross-platform native binaries)
//   3. Walks the directory and emits a JSON mount tree for WebContainer.mount()
//
// The JSON output is a nested object matching the WebContainer FileSystemTree format:
//   { "app": { "directory": { "models": { "directory": { "article.rb": { "file": { "contents": "..." } } } } } } }

import { readFileSync, readdirSync, statSync, existsSync, writeFileSync } from 'node:fs';
import { join, resolve, basename } from 'node:path';
import { execSync } from 'node:child_process';
import { parseArgs } from 'node:util';

const { values: opts, positionals } = parseArgs({
  options: {
    output: { type: 'string', short: 'o' },
    'skip-install': { type: 'boolean', default: false },
  },
  allowPositionals: true,
});

const srcDir = resolve(positionals[0] || 'demo/blog');
const demoName = basename(srcDir);
const outputPath = opts.output || `editor/snapshots/${demoName}.json`;

if (!existsSync(srcDir)) {
  console.error(`Error: ${srcDir} does not exist.`);
  process.exit(1);
}

const ROOT = resolve(import.meta.dirname, '..');

// Step 1: juntos init
if (!existsSync(join(srcDir, 'vite.config.js'))) {
  console.log('Running juntos init...');
  const cliPath = join(ROOT, 'packages', 'juntos-dev', 'cli.mjs');
  execSync(`node ${cliPath} init --no-install`, { cwd: srcDir, stdio: 'inherit' });
}

// Step 2: npm install
if (!opts['skip-install'] && !existsSync(join(srcDir, 'node_modules'))) {
  console.log('Installing dependencies...');
  const tarballs = join(ROOT, 'artifacts', 'tarballs');
  if (existsSync(tarballs)) {
    const pkgs = [
      join(tarballs, 'ruby2js-beta.tgz'),
      join(tarballs, 'juntos-beta.tgz'),
      join(tarballs, 'juntos-dev-beta.tgz'),
      join(tarballs, 'vite-plugin-ruby2js-beta.tgz'),
      'dexie', '@hotwired/turbo', '@hotwired/stimulus', 'react', 'react-dom',
    ].join(' ');
    execSync(`npm install ${pkgs}`, { cwd: srcDir, stdio: 'inherit' });
  } else {
    execSync('npm install', { cwd: srcDir, stdio: 'inherit' });
  }

  // Install cross-platform native binaries for WebContainers (linux-x64-musl)
  console.log('Installing cross-platform native binaries...');
  installCrossPlatformBinary(srcDir, '@rollup/rollup-linux-x64-musl');
  installCrossPlatformBinary(srcDir, '@esbuild/linux-x64');
}

function installCrossPlatformBinary(dir, pkg) {
  const targetDir = join(dir, 'node_modules', ...pkg.split('/'));
  if (existsSync(targetDir)) return;

  try {
    // npm pack downloads the tarball without platform checks
    const result = execSync(`npm pack ${pkg} --pack-destination /tmp`, {
      cwd: dir, stdio: ['pipe', 'pipe', 'pipe'],
    }).toString().trim();
    const tgzPath = join('/tmp', result.split('\n').pop());
    execSync(`mkdir -p "${targetDir}" && tar -xzf "${tgzPath}" -C "${targetDir}" --strip-components=1`);
    execSync(`rm -f "${tgzPath}"`);
    console.log(`  Installed ${pkg}`);
  } catch (err) {
    console.warn(`  Warning: Could not install ${pkg}: ${err.message}`);
  }
}

// Step 3: Walk directory and build mount tree
console.log('Building mount tree...');

const SKIP_DIRS = new Set(['dist', 'tmp', 'log', 'storage', '.git', '.cache']);
const SKIP_FILES = new Set(['.DS_Store']);

function walkDir(dir, relPath) {
  const tree = {};
  let entries;
  try {
    entries = readdirSync(dir);
  } catch {
    return tree;
  }

  for (const name of entries) {
    if (SKIP_FILES.has(name)) continue;
    // Only skip these directories at the top level or known junk
    if (SKIP_DIRS.has(name) && relPath === '') continue;
    if (name === '.cache' && relPath.startsWith('node_modules')) continue;

    const fullPath = join(dir, name);
    let stat;
    try {
      stat = statSync(fullPath);
    } catch {
      continue; // broken symlink etc.
    }

    if (stat.isDirectory()) {
      tree[name] = { directory: walkDir(fullPath, relPath ? `${relPath}/${name}` : name) };
    } else if (stat.isFile()) {
      try {
        const content = readFileSync(fullPath);
        // Try as UTF-8 text first
        const text = content.toString('utf-8');
        // Verify it's valid UTF-8 by checking for replacement chars in binary files
        if (content.length > 0 && !isBinary(content)) {
          tree[name] = { file: { contents: text } };
        } else {
          // Binary file — base64 encode, browser will decode to Uint8Array before mounting
          tree[name] = { file: { contents: content.toString('base64'), binary: true } };
        }
      } catch {
        // Skip unreadable files
      }
    }
    // Skip symlinks — WebContainers doesn't support them
  }

  return tree;
}

function isBinary(buffer) {
  // Check first 8KB for null bytes (simple binary detection)
  const len = Math.min(buffer.length, 8192);
  for (let i = 0; i < len; i++) {
    if (buffer[i] === 0) return true;
  }
  return false;
}

const tree = walkDir(srcDir, '');

// Step 4: Write JSON
const { mkdirSync } = await import('node:fs');
const { dirname } = await import('node:path');
mkdirSync(dirname(resolve(outputPath)), { recursive: true });
writeFileSync(resolve(outputPath), JSON.stringify(tree));

const size = statSync(resolve(outputPath)).size;
console.log(`Snapshot written: ${outputPath} (${(size / 1024 / 1024).toFixed(1)} MB)`);
