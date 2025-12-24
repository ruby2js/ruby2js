#!/usr/bin/env node
// Smoke test for Phlex Components demo builds
// Compares Ruby and selfhost builds, validates JS syntax

import { execSync } from 'child_process';
import { readFileSync, readdirSync, statSync, existsSync, mkdtempSync, rmSync, mkdirSync, writeFileSync } from 'fs';
import { join, relative, dirname } from 'path';
import { tmpdir } from 'os';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const DEMO_ROOT = join(__dirname, '..');
const PROJECT_ROOT = join(DEMO_ROOT, '../..');
const SELFHOST_ROOT = join(PROJECT_ROOT, 'demo/selfhost');

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

const showDiff = process.argv.includes('--diff') || process.argv.includes('-d');

function showUnifiedDiff(content1, content2, label1, label2, filename) {
  const lines1 = content1.split('\n');
  const lines2 = content2.split('\n');

  console.log(`\n${CYAN}--- ${label1}/${filename}${RESET}`);
  console.log(`${CYAN}+++ ${label2}/${filename}${RESET}`);

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

async function checkSyntax(filePath) {
  try {
    const code = readFileSync(filePath, 'utf8');
    const wrappedCode = `
      const Phlex = { HTML: class {} };
      ${code}
    `;
    const dataUrl = `data:text/javascript,${encodeURIComponent(wrappedCode)}`;
    await import(dataUrl);
    return { valid: true, error: null };
  } catch (err) {
    const match = err.message.match(/^(.+?)(?:\n|$)/);
    const shortErr = match ? match[1] : err.message;
    if (shortErr.includes('Failed to resolve module') ||
        shortErr.includes('is not defined')) {
      return { valid: true, error: null };
    }
    return { valid: false, error: shortErr };
  }
}

async function buildWithSelfhost(srcDir, destDir, filterNames = ['phlex', 'functions', 'esm']) {
  const ruby2jsModule = await import(join(SELFHOST_ROOT, 'ruby2js.js'));
  const { convert, initPrism, Ruby2JS } = ruby2jsModule;
  await initPrism();

  // Import all filters that might be needed
  await import(join(SELFHOST_ROOT, 'filters/functions.js'));
  await import(join(SELFHOST_ROOT, 'filters/esm.js'));
  await import(join(SELFHOST_ROOT, 'filters/phlex.js'));

  // Build filter array based on requested filters
  const filterMap = {
    phlex: Ruby2JS.Filter.Phlex,
    functions: Ruby2JS.Filter.Functions,
    esm: Ruby2JS.Filter.ESM
  };

  const filters = filterNames.map(name => filterMap[name]).filter(Boolean);

  const rbFiles = [];
  function findRbFiles(dir) {
    for (const entry of readdirSync(dir)) {
      const path = join(dir, entry);
      const stat = statSync(path);
      if (stat.isDirectory()) {
        findRbFiles(path);
      } else if (entry.endsWith('.rb')) {
        rbFiles.push(path);
      }
    }
  }
  findRbFiles(srcDir);

  for (const rbFile of rbFiles) {
    const source = readFileSync(rbFile, 'utf8');
    const relPath = relative(srcDir, rbFile);
    const destPath = join(destDir, relPath.replace(/\.rb$/, '.js'));

    mkdirSync(dirname(destPath), { recursive: true });

    try {
      const result = convert(source, {
        filters,
        eslevel: 2022,
        autoexports: true,
        comparison: 'identity'
      });
      writeFileSync(destPath, result.to_s);
    } catch (e) {
      throw new Error(`Failed to transpile ${relPath}: ${e.message}`);
    }
  }
}

function compareDirs(dir1, dir2, label1 = 'dir1', label2 = 'dir2') {
  const files1 = collectJsFiles(dir1).map(f => relative(dir1, f)).sort();
  const files2 = collectJsFiles(dir2).map(f => relative(dir2, f)).sort();

  const differences = {
    onlyIn1: [],
    onlyIn2: [],
    contentDiff: []
  };

  for (const f of files1) {
    if (!files2.includes(f)) {
      differences.onlyIn1.push(f);
    }
  }

  for (const f of files2) {
    if (!files1.includes(f)) {
      differences.onlyIn2.push(f);
    }
  }

  const common = files1.filter(f => files2.includes(f));
  for (const f of common) {
    const content1 = readFileSync(join(dir1, f), 'utf8');
    const content2 = readFileSync(join(dir2, f), 'utf8');

    const norm1 = content1.replace(/\/\/# sourceMappingURL=.*$/gm, '').trim();
    const norm2 = content2.replace(/\/\/# sourceMappingURL=.*$/gm, '').trim();

    if (norm1 !== norm2) {
      differences.contentDiff.push({ file: f, content1: norm1, content2: norm2 });
    }
  }

  return { files1, files2, common, differences };
}

async function runTests() {
  log('\n=== Phlex Components Smoke Test ===\n', BOLD);

  let passed = 0;
  let failed = 0;

  const tempDir = mkdtempSync(join(tmpdir(), 'phlex-components-test-'));
  const rubyDist = join(tempDir, 'ruby-dist');
  const selfhostDist = join(tempDir, 'selfhost-dist');

  try {
    log('1. Ruby build', BOLD);
    try {
      mkdirSync(join(rubyDist, 'components'), { recursive: true });
      execSync(`bundle exec ruby demo/phlex-components/scripts/build.rb`, {
        cwd: PROJECT_ROOT,
        encoding: 'utf8',
        stdio: ['pipe', 'pipe', 'pipe']
      });
      const distDir = join(DEMO_ROOT, 'dist/components');
      for (const f of readdirSync(distDir)) {
        if (f.endsWith('.js')) {
          const content = readFileSync(join(distDir, f), 'utf8');
          writeFileSync(join(rubyDist, 'components', f), content);
        }
      }
      pass('Ruby build completed');
      passed++;
    } catch (e) {
      fail(`Ruby build failed: ${e.message}`);
      failed++;
    }

    log('\n2. Selfhost build', BOLD);
    try {
      mkdirSync(join(selfhostDist, 'components'), { recursive: true });
      await buildWithSelfhost(
        join(DEMO_ROOT, 'app/components'),
        join(selfhostDist, 'components')
      );
      pass('Selfhost build completed');
      passed++;
    } catch (e) {
      fail(`Selfhost build failed: ${e.message}`);
      console.error(e);
      failed++;
    }

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

    log('\n5. Compare Ruby vs Selfhost builds', BOLD);
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

  } finally {
    try {
      rmSync(tempDir, { recursive: true, force: true });
    } catch (e) {
      // Ignore cleanup errors
    }
  }

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
