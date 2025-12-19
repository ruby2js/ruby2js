#!/usr/bin/env node
// Smoke test for Rails-in-JS demo builds
// Compares Ruby and selfhost builds, validates JS syntax

import { execSync, spawnSync } from 'child_process';
import { readFileSync, readdirSync, statSync, existsSync, mkdtempSync, rmSync } from 'fs';
import { join, relative } from 'path';
import { tmpdir } from 'os';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const DEMO_ROOT = join(__dirname, '..');

// Parse command line options
const showDiff = process.argv.includes('--diff') || process.argv.includes('-d');

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
function warn(msg) { log(`  ⚠ ${msg}`, YELLOW); }
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

  if (firstDiff === -1) return; // No diff (shouldn't happen)

  // Show context around differences
  const contextLines = 3;
  const start = Math.max(0, firstDiff - contextLines);
  const end = Math.min(maxLen, lastDiff + contextLines + 1);

  console.log(`${CYAN}@@ -${start + 1},${lines1.length} +${start + 1},${lines2.length} @@${RESET}`);

  for (let i = start; i < end; i++) {
    const line1 = lines1[i];
    const line2 = lines2[i];

    if (line1 === line2) {
      // Context line (same in both)
      console.log(` ${line1 ?? ''}`);
    } else {
      // Show removed line (from file1)
      if (line1 !== undefined) {
        console.log(`${RED}-${line1}${RESET}`);
      }
      // Show added line (from file2)
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

// Validate JS file as ES module using dynamic import
async function checkSyntax(filePath) {
  try {
    const code = readFileSync(filePath, 'utf8');
    const dataUrl = `data:text/javascript,${encodeURIComponent(code)}`;
    await import(dataUrl);
    return { valid: true, error: null };
  } catch (err) {
    // Extract just the first line of error message
    const match = err.message.match(/^(.+?)(?:\n|$)/);
    const shortErr = match ? match[1] : err.message;
    // Ignore module resolution errors (imports that don't exist in data URL context)
    if (shortErr.includes('Failed to resolve module')) {
      return { valid: true, error: null };
    }
    return { valid: false, error: shortErr };
  }
}

// Check for common JS syntax issues
function checkCommonIssues(filePath, content) {
  const issues = [];
  const lines = content.split('\n');

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
  log('\n=== Rails-in-JS Smoke Test ===\n', BOLD);

  let passed = 0;
  let failed = 0;
  let warnings = 0;

  const tempDir = mkdtempSync(join(tmpdir(), 'rails-in-js-test-'));
  const rubyDist = join(tempDir, 'ruby-dist');
  const selfhostDist = join(tempDir, 'selfhost-dist');

  try {
    // Test 1: Ruby build
    log('1. Ruby build', BOLD);
    try {
      execSync(`ruby scripts/build.rb "${rubyDist}"`, {
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
      // Import and run selfhost builder
      const { SelfhostBuilder } = await import(join(DEMO_ROOT, 'scripts/build-selfhost.mjs'));
      const builder = new SelfhostBuilder(selfhostDist);
      await builder.build();
      pass('Selfhost build completed');
      passed++;
    } catch (e) {
      fail(`Selfhost build failed: ${e.message}`);
      failed++;
    }

    // Test 3: Syntax check on Ruby-built files
    log('\n3. JS syntax check (Ruby build)', BOLD);
    const rubyFiles = collectJsFiles(rubyDist);
    let syntaxErrors = 0;

    for (const file of rubyFiles) {
      const result = await checkSyntax(file);
      if (!result.valid) {
        fail(`${relative(rubyDist, file)}: ${result.error}`);
        syntaxErrors++;
      }
    }

    if (syntaxErrors === 0) {
      pass(`All ${rubyFiles.length} files have valid syntax`);
      passed++;
    } else {
      fail(`${syntaxErrors} files have syntax errors`);
      failed++;
    }

    // Test 4: Syntax check on selfhost-built files
    log('\n4. JS syntax check (Selfhost build)', BOLD);
    const selfhostFiles = collectJsFiles(selfhostDist);
    syntaxErrors = 0;

    for (const file of selfhostFiles) {
      const result = await checkSyntax(file);
      if (!result.valid) {
        fail(`${relative(selfhostDist, file)}: ${result.error}`);
        syntaxErrors++;
      }
    }

    if (syntaxErrors === 0) {
      pass(`All ${selfhostFiles.length} files have valid syntax`);
      passed++;
    } else {
      fail(`${syntaxErrors} files have syntax errors`);
      failed++;
    }

    // Test 5: Common issues check
    log('\n5. Common issues check (Ruby build)', BOLD);
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

    // Test 6: Compare builds
    log('\n6. Compare Ruby vs Selfhost builds', BOLD);
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

    // Test 7: Check all imports resolve
    log('\n7. Import resolution check (Ruby build)', BOLD);
    let unresolvedImports = 0;

    for (const file of rubyFiles) {
      const content = readFileSync(file, 'utf8');
      const importMatches = content.matchAll(/import\s+.*?\s+from\s+['"]([^'"]+)['"]/g);

      for (const match of importMatches) {
        const importPath = match[1];
        if (importPath.startsWith('.')) {
          const resolved = join(dirname(file), importPath);
          // Try with and without .js extension
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
  if (warnings > 0) log(`  Warnings: ${warnings}`, YELLOW);
  log('');

  process.exit(failed > 0 ? 1 : 0);
}

runTests().catch(e => {
  console.error('Smoke test crashed:', e);
  process.exit(1);
});
