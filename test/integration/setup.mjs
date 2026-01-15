#!/usr/bin/env node
// Setup script for integration tests
// Downloads tarballs from releases and builds a demo for testing
//
// Usage:
//   node setup.mjs                    # Download everything from GitHub Pages releases
//   node setup.mjs --local            # Use local artifacts/ for everything
//   node setup.mjs --local-packages   # Download demo, use local npm package tarballs
//   node setup.mjs blog               # Specify demo name (default: blog)

import { execSync } from 'child_process';
import { existsSync, mkdirSync, rmSync, createWriteStream } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { pipeline } from 'stream/promises';

const __dirname = dirname(fileURLToPath(import.meta.url));
const RELEASES_URL = 'https://ruby2js.github.io/ruby2js/releases';
const WORK_DIR = join(__dirname, 'workspace');
const PROJECT_ROOT = join(__dirname, '../..');

const useLocal = process.argv.includes('--local');
const useLocalPackages = process.argv.includes('--local-packages');
// Find demo name: skip node executable, script path, and flags
const demo = process.argv.slice(2).find(arg => !arg.startsWith('-')) || 'blog';
// Tarball names use hyphens (demo-photo-gallery), directories use underscores (photo_gallery)
const demoHyphen = demo.replace(/_/g, '-');

const sourceDesc = useLocal ? 'local artifacts (all)'
  : useLocalPackages ? 'remote demo + local packages'
  : 'GitHub Pages releases';

console.log(`Setting up integration tests for: ${demo}`);
console.log(`Source: ${sourceDesc}\n`);

// Create workspace if it doesn't exist
mkdirSync(WORK_DIR, { recursive: true });

// Clean existing demo directory if it exists
const existingDemo = join(WORK_DIR, demo);
if (existsSync(existingDemo)) {
  console.log(`Removing existing ${demo} directory...`);
  rmSync(existingDemo, { recursive: true });
}

async function downloadFile(url, dest) {
  console.log(`  Downloading ${url}...`);
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Failed to download ${url}: ${response.status}`);
  }
  const fileStream = createWriteStream(dest);
  await pipeline(response.body, fileStream);
}

async function setup() {
  const tarballs = join(WORK_DIR, 'tarballs');
  mkdirSync(tarballs, { recursive: true });

  if (useLocal) {
    // Copy everything from local artifacts
    const localTarballs = join(PROJECT_ROOT, 'artifacts/tarballs');
    if (!existsSync(localTarballs)) {
      console.error('Local artifacts not found. Run: bundle exec rake -f demo/selfhost/Rakefile release');
      process.exit(1);
    }
    console.log('1. Copying local tarballs...');
    execSync(`cp ${localTarballs}/*.tgz ${tarballs}/`);
    // CI downloads artifact to artifacts/demo-*.tar.gz directly
    // Local rake builds to artifacts/demo-*/demo-*.tar.gz
    const ciPath = join(PROJECT_ROOT, `artifacts/demo-${demoHyphen}.tar.gz`);
    const localPath = join(PROJECT_ROOT, `artifacts/demo-${demoHyphen}/demo-${demoHyphen}.tar.gz`);
    const demoTarball = existsSync(ciPath) ? ciPath : localPath;
    execSync(`cp ${demoTarball} ${tarballs}/`);
  } else if (useLocalPackages) {
    // Download demo from releases, use local npm packages
    const localTarballs = join(PROJECT_ROOT, 'artifacts/tarballs');
    if (!existsSync(localTarballs)) {
      console.error('Local package tarballs not found. Run: bundle exec rake -f demo/selfhost/Rakefile release');
      process.exit(1);
    }
    console.log('1. Downloading demo tarball + copying local packages...');
    await downloadFile(`${RELEASES_URL}/demo-${demoHyphen}.tar.gz`, join(tarballs, `demo-${demoHyphen}.tar.gz`));
    execSync(`cp ${localTarballs}/*.tgz ${tarballs}/`);
  } else {
    // Download everything from releases
    console.log('1. Downloading tarballs from releases...');
    await downloadFile(`${RELEASES_URL}/ruby2js-beta.tgz`, join(tarballs, 'ruby2js-beta.tgz'));
    await downloadFile(`${RELEASES_URL}/ruby2js-rails-beta.tgz`, join(tarballs, 'ruby2js-rails-beta.tgz'));
    await downloadFile(`${RELEASES_URL}/demo-${demoHyphen}.tar.gz`, join(tarballs, `demo-${demoHyphen}.tar.gz`));
  }

  // Extract demo
  console.log(`\n2. Extracting ${demo} demo...`);
  execSync(`tar -xzf ${tarballs}/demo-${demoHyphen}.tar.gz -C ${WORK_DIR}`);

  const demoDir = join(WORK_DIR, demo);
  const distDir = join(demoDir, 'dist');

  // Install dependencies in dist/ (where package.json lives and builder looks for adapters)
  console.log('\n3. Installing dependencies in dist/...');
  execSync(`npm install ${tarballs}/ruby2js-beta.tgz ${tarballs}/ruby2js-rails-beta.tgz`, {
    cwd: distDir,
    stdio: 'inherit'
  });

  // Install better-sqlite3 in dist/ for the demo
  execSync('npm install better-sqlite3', {
    cwd: distDir,
    stdio: 'inherit'
  });

  // Build with browser target but better-sqlite3 adapter (for Node.js testing)
  // vite: false ensures .js imports instead of .html.erb (no Vite transform in Node)
  console.log('\n4. Building demo with better-sqlite3 + browser target...');

  // Use the Ruby builder since it's more reliable
  // Point to the local ruby2js gem for building
  execSync(
    `BUNDLE_GEMFILE="${PROJECT_ROOT}/Gemfile" bundle exec ruby -r ruby2js/rails/builder -e "SelfhostBuilder.new('dist', database: 'sqlite', target: 'browser', vite: false).build"`,
    {
      cwd: demoDir,
      stdio: 'inherit'
    }
  );

  // When using local packages, reinstall them in dist/ to override the build's npm install
  // (the build's package.json has hardcoded URLs to released packages)
  // Also copy rails.js to lib/ since build already copied it before reinstall
  if (useLocal || useLocalPackages) {
    console.log('\n5. Reinstalling local packages in dist/...');
    execSync(`npm install ${tarballs}/ruby2js-rails-beta.tgz`, {
      cwd: distDir,
      stdio: 'inherit'
    });
    // Copy the updated rails.js to lib/ (build copied it before reinstall)
    execSync(`cp "${distDir}/node_modules/ruby2js-rails/targets/browser/rails.js" "${distDir}/lib/rails.js"`, {
      stdio: 'inherit'
    });
    console.log('\n6. Setup complete!');
  } else {
    // When using remote packages, apply local rails.js to get latest fixes
    console.log('\n5. Applying local rails.js (workaround for remote packages)...');
    execSync(`cp "${PROJECT_ROOT}/packages/ruby2js-rails/targets/browser/rails.js" "${distDir}/lib/rails.js"`, {
      stdio: 'inherit'
    });
    console.log('\n6. Setup complete!');
  }
  console.log(`   Demo built at: ${demoDir}/dist`);
  console.log('   Run tests with: npm test');
}

setup().catch(err => {
  console.error('Setup failed:', err);
  process.exit(1);
});
