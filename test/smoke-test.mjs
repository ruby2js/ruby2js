#!/usr/bin/env node
// Smoke test for Ruby2JS demo builds
// Compares Ruby and selfhost builds
//
// Usage: node test/smoke-test.mjs <demo-directory> [options]
//        node test/smoke-test.mjs demo/blog --database dexie
//        node test/smoke-test.mjs demo/chat --database sqlite --diff
//        node test/smoke-test.mjs demo/blog --target browser --database dexie

import { execSync } from 'child_process';
import { readFileSync, readdirSync, statSync, existsSync, mkdtempSync, rmSync } from 'fs';
import { join, relative, dirname } from 'path';
import { tmpdir } from 'os';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const PROJECT_ROOT = join(__dirname, '..');

// Try node_modules first (CI with installed tarball), then packages (local dev)
const PACKAGE_LOCATIONS = [
  join(PROJECT_ROOT, 'node_modules/ruby2js-rails'),
  join(PROJECT_ROOT, 'packages/ruby2js-rails')
];
const PACKAGE_ROOT = PACKAGE_LOCATIONS.find(p => existsSync(join(p, 'build.mjs'))) || PACKAGE_LOCATIONS[1];

// Parse command line
const args = process.argv.slice(2);
const showDiff = args.includes('--diff') || args.includes('-d');

// Parse --database or -db argument
let database = null;
const dbIndex = args.findIndex(arg => arg === '--database' || arg === '-db');
if (dbIndex !== -1 && args[dbIndex + 1]) {
  database = args[dbIndex + 1];
}

// Parse --target or -t argument
let target = null;
const targetIndex = args.findIndex(arg => arg === '--target' || arg === '-t');
if (targetIndex !== -1 && args[targetIndex + 1]) {
  target = args[targetIndex + 1];
}

const demoDir = args.find(arg => !arg.startsWith('-') && arg !== database && arg !== target);

if (!demoDir) {
  console.error('Usage: node test/smoke-test.mjs <demo-directory> [options]');
  console.error('');
  console.error('Options:');
  console.error('  --database, -db  Database adapter (dexie, sqljs, sqlite, etc.)');
  console.error('  --target, -t     Build target (node, browser)');
  console.error('  --diff, -d       Show unified diff for content differences');
  console.error('');
  console.error('Example:');
  console.error('  node test/smoke-test.mjs demo/blog');
  console.error('  node test/smoke-test.mjs demo/blog --database dexie');
  console.error('  node test/smoke-test.mjs demo/chat --database sqlite --diff');
  console.error('  node test/smoke-test.mjs demo/blog --target browser --database dexie');
  process.exit(1);
}

const DEMO_ROOT = join(PROJECT_ROOT, demoDir);

if (!existsSync(DEMO_ROOT)) {
  console.error(`Demo directory not found: ${DEMO_ROOT}`);
  process.exit(1);
}

// ANSI colors
const GREEN = '\x1b[32m';
const RED = '\x1b[31m';
const YELLOW = '\x1b[33m';
const CYAN = '\x1b[36m';
const RESET = '\x1b[0m';
const BOLD = '\x1b[1m';

function log(msg, color = '') {
  console.log(`${color}${msg}${RESET}`);
}

function pass(msg) { log(`  ✓ ${msg}`, GREEN); }
function fail(msg) { log(`  ✗ ${msg}`, RED); }
function info(msg) { log(`  ${msg}`, CYAN); }

// Simple unified diff output
function showUnifiedDiff(content1, content2, label1, label2, filename) {
  const lines1 = content1.split('\n');
  const lines2 = content2.split('\n');

  console.log(`\n${CYAN}--- ${label1}/${filename}${RESET}`);
  console.log(`${CYAN}+++ ${label2}/${filename}${RESET}`);

  // Find first and last differing lines for context
  let firstDiff = -1;
  let lastDiff = -1;
  const maxLen = Math.max(lines1.length, lines2.length);

  for (let i = 0; i < maxLen; i++) {
    if (lines1[i] !== lines2[i]) {
      if (firstDiff === -1) firstDiff = i;
      lastDiff = i;
    }
  }

  if (firstDiff === -1) return;

  // Show context around differences
  const contextLines = 3;
  const start = Math.max(0, firstDiff - contextLines);
  const end = Math.min(maxLen, lastDiff + contextLines + 1);

  console.log(`${CYAN}@@ -${start + 1},${lines1.length} +${start + 1},${lines2.length} @@${RESET}`);

  for (let i = start; i < end; i++) {
    const line1 = lines1[i];
    const line2 = lines2[i];

    if (line1 === line2) {
      console.log(` ${line1 ?? ''}`);
    } else {
      if (line1 !== undefined) {
        console.log(`${RED}-${line1}${RESET}`);
      }
      if (line2 !== undefined) {
        console.log(`${GREEN}+${line2}${RESET}`);
      }
    }
  }
}

// Collect all .js files in a directory recursively
function collectJsFiles(dir, files = []) {
  if (!existsSync(dir)) return files;

  for (const entry of readdirSync(dir)) {
    const path = join(dir, entry);
    const stat = statSync(path);

    if (stat.isDirectory()) {
      collectJsFiles(path, files);
    } else if (entry.endsWith('.js') || entry.endsWith('.mjs')) {
      files.push(path);
    }
  }

  return files;
}

// Check for common JS syntax issues
function checkCommonIssues(filePath, content) {
  const issues = [];

  // Check for 'export import' (invalid syntax)
  if (/export\s+import\s/.test(content)) {
    issues.push('Contains "export import" (invalid syntax)');
  }

  // Check for empty export
  if (/export\s*{\s*}\s*from/.test(content)) {
    issues.push('Contains empty export {}');
  }

  // Check for undefined references in common patterns
  if (/\.to_s\(\)/.test(content)) {
    issues.push('Contains .to_s() (Ruby method, not JS)');
  }

  // Check for unresolved template literals
  if (/#\{[^}]+\}/.test(content)) {
    issues.push('Contains Ruby string interpolation #{} instead of ${}');
  }

  return issues;
}

// Compare two directories
function compareDirs(dir1, dir2, label1 = 'dir1', label2 = 'dir2') {
  const files1 = collectJsFiles(dir1).map(f => relative(dir1, f)).sort();
  const files2 = collectJsFiles(dir2).map(f => relative(dir2, f)).sort();

  const differences = {
    onlyIn1: [],
    onlyIn2: [],
    contentDiff: []
  };

  // Files only in dir1
  for (const f of files1) {
    if (!files2.includes(f)) {
      differences.onlyIn1.push(f);
    }
  }

  // Files only in dir2
  for (const f of files2) {
    if (!files1.includes(f)) {
      differences.onlyIn2.push(f);
    }
  }

  // Compare content of common files
  const common = files1.filter(f => files2.includes(f));
  for (const f of common) {
    const content1 = readFileSync(join(dir1, f), 'utf8');
    const content2 = readFileSync(join(dir2, f), 'utf8');

    // Normalize: remove sourcemap comments, trailing whitespace
    const norm1 = content1.replace(/\/\/# sourceMappingURL=.*$/gm, '').trim();
    const norm2 = content2.replace(/\/\/# sourceMappingURL=.*$/gm, '').trim();

    if (norm1 !== norm2) {
      differences.contentDiff.push({ file: f, content1: norm1, content2: norm2 });
    }
  }

  return { files1, files2, common, differences };
}

// Main test runner
async function runTests() {
  const demoName = demoDir.split('/').pop();
  const optLabels = [database, target].filter(Boolean).join(', ');
  const optLabel = optLabels ? ` (${optLabels})` : '';
  log(`\n=== Smoke Test: ${demoName}${optLabel} ===\n`, BOLD);

  let passed = 0;
  let failed = 0;

  const tempDir = mkdtempSync(join(tmpdir(), `ruby2js-${demoName}-test-`));
  const rubyDist = join(tempDir, 'ruby-dist');
  const selfhostDist = join(tempDir, 'selfhost-dist');

  try {
    // Test 1: Ruby build
    // Note: Run from demo directory to get correct DEMO_ROOT, but use project root's Gemfile
    // The demo's Gemfile uses ruby2js from GitHub, but we want to test local changes
    log('1. Ruby build', BOLD);
    try {
      const optArgs = [
        database ? `database: '${database}'` : null,
        target ? `target: '${target}'` : null
      ].filter(Boolean).join(', ');
      const optStr = optArgs ? `, ${optArgs}` : '';
      execSync(`BUNDLE_GEMFILE="${PROJECT_ROOT}/Gemfile" bundle exec ruby -r ruby2js/rails/builder -e "SelfhostBuilder.new('${rubyDist}'${optStr}).build"`, {
        cwd: DEMO_ROOT,
        encoding: 'utf8',
        stdio: ['pipe', 'pipe', 'pipe']
      });
      pass('Ruby build completed');
      passed++;
    } catch (e) {
      fail(`Ruby build failed: ${e.message}`);
      failed++;
    }

    // Test 2: Selfhost build
    log('\n2. Selfhost build', BOLD);
    try {
      // Change to demo directory so DEMO_ROOT (process.cwd()) is correct
      // The JS builder uses process.cwd() to find app files and ../../packages/
      const originalCwd = process.cwd();
      const originalDb = process.env.JUNTOS_DATABASE;
      process.chdir(DEMO_ROOT);
      if (database) {
        process.env.JUNTOS_DATABASE = database;
      }
      try {
        const { SelfhostBuilder } = await import(join(PACKAGE_ROOT, 'build.mjs'));
        const options = {};
        if (database) options.database = database;
        if (target) options.target = target;
        const builder = new SelfhostBuilder(selfhostDist, options);
        await builder.build();
        pass('Selfhost build completed');
        passed++;
      } finally {
        process.chdir(originalCwd);
        if (originalDb !== undefined) {
          process.env.JUNTOS_DATABASE = originalDb;
        } else {
          delete process.env.JUNTOS_DATABASE;
        }
      }
    } catch (e) {
      fail(`Selfhost build failed: ${e.message || e}`);
      if (e.stack) {
        console.error(e.stack);
      }
      failed++;
    }

    // Collect files for remaining tests
    const rubyFiles = collectJsFiles(rubyDist);

    // Test 3: Common issues check
    log('\n3. Common issues check (Ruby build)', BOLD);
    let issueCount = 0;

    for (const file of rubyFiles) {
      const content = readFileSync(file, 'utf8');
      const issues = checkCommonIssues(file, content);

      for (const issue of issues) {
        fail(`${relative(rubyDist, file)}: ${issue}`);
        issueCount++;
      }
    }

    if (issueCount === 0) {
      pass('No common issues found');
      passed++;
    } else {
      failed++;
    }

    // Test 4: Compare builds
    log('\n4. Compare Ruby vs Selfhost builds', BOLD);
    const comparison = compareDirs(rubyDist, selfhostDist, 'ruby', 'selfhost');

    if (comparison.differences.onlyIn1.length > 0) {
      fail(`Files only in Ruby build: ${comparison.differences.onlyIn1.join(', ')}`);
      failed++;
    }

    if (comparison.differences.onlyIn2.length > 0) {
      fail(`Files only in Selfhost build: ${comparison.differences.onlyIn2.join(', ')}`);
      failed++;
    }

    if (comparison.differences.contentDiff.length > 0) {
      for (const diff of comparison.differences.contentDiff) {
        fail(`Content differs: ${diff.file}`);
        if (showDiff) {
          showUnifiedDiff(diff.content1, diff.content2, 'ruby', 'selfhost', diff.file);
        }
      }
      if (!showDiff && comparison.differences.contentDiff.length > 0) {
        info('Run with --diff to see differences');
      }
      failed++;
    } else if (comparison.differences.onlyIn1.length === 0 && comparison.differences.onlyIn2.length === 0) {
      pass('Builds are identical');
      passed++;
    }

    // Test 5: Check all imports resolve
    log('\n5. Import resolution check (Ruby build)', BOLD);
    let unresolvedImports = 0;

    for (const file of rubyFiles) {
      const content = readFileSync(file, 'utf8');
      const importMatches = content.matchAll(/import\s+.*?\s+from\s+['"]([^'"]+)['"]/g);

      for (const match of importMatches) {
        const importPath = match[1];
        if (importPath.startsWith('.')) {
          const resolved = join(dirname(file), importPath);
          const exists = existsSync(resolved) ||
                        existsSync(resolved + '.js') ||
                        existsSync(resolved + '.mjs');

          if (!exists) {
            fail(`${relative(rubyDist, file)}: Cannot resolve "${importPath}"`);
            unresolvedImports++;
          }
        }
      }
    }

    if (unresolvedImports === 0) {
      pass('All relative imports resolve');
      passed++;
    } else {
      failed++;
    }

  } finally {
    // Cleanup
    try {
      rmSync(tempDir, { recursive: true, force: true });
    } catch (e) {
      // Ignore cleanup errors
    }
  }

  // Summary
  log('\n=== Summary ===', BOLD);
  log(`  Passed:   ${passed}`, GREEN);
  if (failed > 0) log(`  Failed:   ${failed}`, RED);
  log('');

  process.exit(failed > 0 ? 1 : 0);
}

runTests().catch(e => {
  console.error('Smoke test crashed:', e);
  process.exit(1);
});
