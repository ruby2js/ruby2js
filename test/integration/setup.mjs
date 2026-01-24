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

  // Special handling for static site demos (not Rails)
  if (demo === 'astro_blog') {
    await setupAstroBlog(tarballs);
    return;
  }

  if (demo === 'ssg_blog') {
    await setupSsgBlog(tarballs);
    return;
  }

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

  // Vite-native architecture: package.json is at app root, not dist/
  // Install dependencies at app root where package.json lives
  console.log('\n3. Installing dependencies...');
  execSync(`npm install ${tarballs}/ruby2js-beta.tgz ${tarballs}/ruby2js-rails-beta.tgz`, {
    cwd: demoDir,
    stdio: 'inherit'
  });

  // Install better-sqlite3 for the demo (Node.js testing)
  execSync('npm install better-sqlite3', {
    cwd: demoDir,
    stdio: 'inherit'
  });

  // Build with Vite using better-sqlite3 adapter and node target
  // This is the Vite-native approach - testing the actual build pipeline
  console.log('\n4. Building demo with Vite (sqlite + node target)...');

  execSync('JUNTOS_DATABASE=sqlite JUNTOS_TARGET=node npm run build', {
    cwd: demoDir,
    stdio: 'inherit'
  });

  console.log('\n5. Setup complete!');
  console.log(`   Demo built at: ${demoDir}/dist`);
  console.log('   Run tests with: npm test');
}

async function setupAstroBlog(tarballs) {
  // Astro blog is a static site - different setup than Rails demos
  // 1. Download/copy tarballs (ruby2js + ruby2js-astro)
  // 2. Extract demo tarball
  // 3. Install dependencies from tarballs
  // 4. Build the static site

  if (useLocal) {
    const localTarballs = join(PROJECT_ROOT, 'artifacts/tarballs');
    if (!existsSync(localTarballs)) {
      console.error('Local artifacts not found. Run: bundle exec rake -f demo/selfhost/Rakefile release');
      process.exit(1);
    }
    console.log('1. Copying local tarballs...');
    execSync(`cp ${localTarballs}/*.tgz ${tarballs}/`);
    // CI downloads artifact to artifacts/demo-*.tar.gz directly
    // Local rake builds to artifacts/demo-*/demo-*.tar.gz
    const ciPath = join(PROJECT_ROOT, 'artifacts/demo-astro-blog.tar.gz');
    const localPath = join(PROJECT_ROOT, 'artifacts/demo-astro-blog/demo-astro-blog.tar.gz');
    const demoTarball = existsSync(ciPath) ? ciPath : localPath;
    execSync(`cp ${demoTarball} ${tarballs}/`);
  } else if (useLocalPackages) {
    const localTarballs = join(PROJECT_ROOT, 'artifacts/tarballs');
    if (!existsSync(localTarballs)) {
      console.error('Local package tarballs not found. Run: bundle exec rake -f demo/selfhost/Rakefile release');
      process.exit(1);
    }
    console.log('1. Downloading demo tarball + copying local packages...');
    await downloadFile(`${RELEASES_URL}/demo-astro-blog.tar.gz`, join(tarballs, 'demo-astro-blog.tar.gz'));
    execSync(`cp ${localTarballs}/*.tgz ${tarballs}/`);
  } else {
    console.log('1. Downloading tarballs from releases...');
    await downloadFile(`${RELEASES_URL}/ruby2js-beta.tgz`, join(tarballs, 'ruby2js-beta.tgz'));
    await downloadFile(`${RELEASES_URL}/ruby2js-astro-beta.tgz`, join(tarballs, 'ruby2js-astro-beta.tgz'));
    await downloadFile(`${RELEASES_URL}/demo-astro-blog.tar.gz`, join(tarballs, 'demo-astro-blog.tar.gz'));
  }

  // Extract demo
  console.log('\n2. Extracting astro_blog demo...');
  execSync(`tar -xzf ${tarballs}/demo-astro-blog.tar.gz -C ${WORK_DIR}`);
  // Rename to use underscore for consistency with test file naming
  const extractedDir = join(WORK_DIR, 'astro-blog');
  const demoDir = join(WORK_DIR, 'astro_blog');
  if (existsSync(extractedDir)) {
    execSync(`mv ${extractedDir} ${demoDir}`);
  }

  // Install dependencies from tarballs
  console.log('\n3. Installing dependencies...');
  execSync(`npm install ${tarballs}/ruby2js-beta.tgz ${tarballs}/ruby2js-astro-beta.tgz`, {
    cwd: demoDir,
    stdio: 'inherit'
  });

  // Build the static site
  console.log('\n4. Building Astro site...');
  execSync('npm run build', {
    cwd: demoDir,
    stdio: 'inherit'
  });

  console.log('\n5. Setup complete!');
  console.log(`   Demo built at: ${demoDir}/dist`);
  console.log('   Run tests with: npm test -- astro_blog.test.mjs');
}

async function setupSsgBlog(tarballs) {
  // SSG blog is a static 11ty site - simplest setup
  // 1. Download/copy tarballs (content-adapter)
  // 2. Extract demo tarball
  // 3. Install dependencies from tarballs
  // 4. Build the static site

  if (useLocal) {
    const localTarballs = join(PROJECT_ROOT, 'artifacts/tarballs');
    if (!existsSync(localTarballs)) {
      console.error('Local artifacts not found. Run: bundle exec rake -f demo/selfhost/Rakefile release');
      process.exit(1);
    }
    console.log('1. Copying local tarballs...');
    execSync(`cp ${localTarballs}/*.tgz ${tarballs}/`);
    // CI downloads artifact to artifacts/demo-*.tar.gz directly
    // Local rake builds to artifacts/demo-*/demo-*.tar.gz
    const ciPath = join(PROJECT_ROOT, 'artifacts/demo-ssg-blog.tar.gz');
    const localPath = join(PROJECT_ROOT, 'artifacts/demo-ssg-blog/demo-ssg-blog.tar.gz');
    const demoTarball = existsSync(ciPath) ? ciPath : localPath;
    execSync(`cp ${demoTarball} ${tarballs}/`);
  } else if (useLocalPackages) {
    const localTarballs = join(PROJECT_ROOT, 'artifacts/tarballs');
    if (!existsSync(localTarballs)) {
      console.error('Local package tarballs not found. Run: bundle exec rake -f demo/selfhost/Rakefile release');
      process.exit(1);
    }
    console.log('1. Downloading demo tarball + copying local packages...');
    await downloadFile(`${RELEASES_URL}/demo-ssg-blog.tar.gz`, join(tarballs, 'demo-ssg-blog.tar.gz'));
    execSync(`cp ${localTarballs}/*.tgz ${tarballs}/`);
  } else {
    console.log('1. Downloading tarballs from releases...');
    await downloadFile(`${RELEASES_URL}/ruby2js-content-adapter-beta.tgz`, join(tarballs, 'ruby2js-content-adapter-beta.tgz'));
    await downloadFile(`${RELEASES_URL}/demo-ssg-blog.tar.gz`, join(tarballs, 'demo-ssg-blog.tar.gz'));
  }

  // Extract demo
  console.log('\n2. Extracting ssg_blog demo...');
  execSync(`tar -xzf ${tarballs}/demo-ssg-blog.tar.gz -C ${WORK_DIR}`);
  // Rename to use underscore for consistency with test file naming
  const extractedDir = join(WORK_DIR, 'ssg-blog');
  const demoDir = join(WORK_DIR, 'ssg_blog');
  if (existsSync(extractedDir)) {
    execSync(`mv ${extractedDir} ${demoDir}`);
  }

  // Install dependencies from tarballs
  console.log('\n3. Installing dependencies...');
  execSync(`npm install ${tarballs}/ruby2js-content-adapter-beta.tgz`, {
    cwd: demoDir,
    stdio: 'inherit'
  });

  // Build the static site
  console.log('\n4. Building 11ty site...');
  execSync('npm run build', {
    cwd: demoDir,
    stdio: 'inherit'
  });

  console.log('\n5. Setup complete!');
  console.log(`   Demo built at: ${demoDir}/_site`);
  console.log('   Run tests with: npm test -- ssg_blog.test.mjs');
}

setup().catch(err => {
  console.error('Setup failed:', err);
  process.exit(1);
});
