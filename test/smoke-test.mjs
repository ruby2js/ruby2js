#!/usr/bin/env node
// Smoke test for Ruby2JS demo builds
// Tests the Vite-based build pipeline (juntos build)
//
// Usage: node test/smoke-test.mjs <demo-directory> [options]
//        node test/smoke-test.mjs demo/blog --database dexie
//        node test/smoke-test.mjs demo/chat --database sqlite --diff

import { execSync } from 'child_process';
import { readFileSync, readdirSync, statSync, existsSync, mkdtempSync, rmSync } from 'fs';
import { join, relative, dirname } from 'path';
import { tmpdir } from 'os';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const PROJECT_ROOT = join(__dirname, '..');

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
const CYAN = '\x1b[36m';
const RESET = '\x1b[0m';
const BOLD = '\x1b[1m';

function log(msg, color = '') {
  console.log(`${color}${msg}${RESET}`);
}

function pass(msg) { log(`  ✓ ${msg}`, GREEN); }
function fail(msg) { log(`  ✗ ${msg}`, RED); }
function info(msg) { log(`  ${msg}`, CYAN); }

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

// Main test runner
async function runTests() {
  const demoName = demoDir.split('/').pop();
  const optLabels = [database, target].filter(Boolean).join(', ');
  const optLabel = optLabels ? ` (${optLabels})` : '';
  log(`\n=== Smoke Test: ${demoName}${optLabel} ===\n`, BOLD);

  let passed = 0;
  let failed = 0;

  // Test 1: juntos eject build
  log('1. Juntos eject build', BOLD);
  const tempDir = mkdtempSync(join(tmpdir(), `ruby2js-${demoName}-test-`));
  const ejectDist = join(tempDir, 'eject-dist');

  try {
    const envVars = [];
    if (database) envVars.push(`JUNTOS_DATABASE=${database}`);
    if (target) envVars.push(`JUNTOS_TARGET=${target}`);
    const envStr = envVars.length > 0 ? envVars.join(' ') + ' ' : '';

    execSync(`${envStr}node ${join(PROJECT_ROOT, 'packages/juntos-dev/cli.mjs')} eject --output ${ejectDist}`, {
      cwd: DEMO_ROOT,
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe']
    });
    pass('Eject build completed');
    passed++;
  } catch (e) {
    fail(`Eject build failed: ${e.stderr || e.message}`);
    failed++;
  }

  // Collect files for remaining tests
  const jsFiles = collectJsFiles(ejectDist);

  // Test 2: Common issues check
  log('\n2. Common issues check', BOLD);
  let issueCount = 0;

  for (const file of jsFiles) {
    const content = readFileSync(file, 'utf8');
    const issues = checkCommonIssues(file, content);

    for (const issue of issues) {
      fail(`${relative(ejectDist, file)}: ${issue}`);
      issueCount++;
    }
  }

  if (issueCount === 0) {
    pass('No common issues found');
    passed++;
  } else {
    failed++;
  }

  // Test 3: Check all imports resolve
  log('\n3. Import resolution check', BOLD);
  let unresolvedImports = 0;

  for (const file of jsFiles) {
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
          fail(`${relative(ejectDist, file)}: Cannot resolve "${importPath}"`);
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

  // Cleanup
  try {
    rmSync(tempDir, { recursive: true, force: true });
  } catch (e) {
    // Ignore cleanup errors
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
