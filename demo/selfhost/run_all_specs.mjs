#!/usr/bin/env node
// Run all specs based on spec_manifest.json
// - "ready" specs must pass (CI fails if they don't)
// - "partial" specs are run but don't fail CI
// - "blocked" specs are skipped with explanation
//
// Options:
//   --skip-transpile  Skip transpilation (use pre-built dist/*.mjs files)
//   --ready-only      Only run "ready" specs (skip partial and blocked)
//   --partial-only    Only run "partial" specs (skip ready and blocked)
//   --verbose         Show failure details for all specs (including partial)

import { execSync } from 'child_process';
import { readFileSync, existsSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const manifest = JSON.parse(readFileSync(join(__dirname, 'spec_manifest.json'), 'utf-8'));
const skipTranspile = process.argv.includes('--skip-transpile');
const readyOnly = process.argv.includes('--ready-only');
const partialOnly = process.argv.includes('--partial-only');
const verbose = process.argv.includes('--verbose');

// Import test harness for running specs in-process
import { initPrism, runTests, resetTests, getTestResults, describe, it, skip, before } from './test_harness.mjs';

// Initialize Prism once at startup
let prismInitialized = false;
async function ensurePrismInitialized() {
  if (!prismInitialized) {
    await initPrism();
    prismInitialized = true;
  }
}

// Colors for output
const colors = {
  green: '\x1b[32m',
  red: '\x1b[31m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  reset: '\x1b[0m',
  bold: '\x1b[1m'
};

function log(color, message) {
  console.log(`${colors[color]}${message}${colors.reset}`);
}

function transpileSpec(specName) {
  const specPath = `../../spec/${specName}`;
  const outputPath = `dist/${specName.replace('.rb', '.mjs')}`;

  // If skip-transpile is set, just check if the file exists
  if (skipTranspile) {
    if (existsSync(join(__dirname, outputPath))) {
      return true;
    }
    log('red', `  Pre-built file not found: ${outputPath}`);
    return false;
  }

  try {
    execSync(`bundle exec ruby scripts/transpile_spec.rb ${specPath} > ${outputPath}`, {
      cwd: __dirname,
      stdio: ['pipe', 'pipe', 'pipe']
    });
    return true;
  } catch (e) {
    log('red', `  Failed to transpile ${specName}: ${e.message}`);
    return false;
  }
}

async function runSpec(specName) {
  const specPath = `./dist/${specName.replace('.rb', '.mjs')}`;

  try {
    await ensurePrismInitialized();

    // Reset test state before running each spec
    resetTests();

    // Import and run the spec (cache bust to ensure fresh import)
    const specModule = await import(specPath + '?t=' + Date.now());

    // Get results directly from test harness
    const results = getTestResults();

    return {
      total: results.total,
      passed: results.passed,
      failed: results.failed,
      skipped: results.skipped,
      failures: results.failures,
      exitCode: results.failed === 0 ? 0 : 1
    };
  } catch (e) {
    return {
      total: 0,
      passed: 0,
      failed: 0,
      skipped: 0,
      failures: [],
      exitCode: 1,
      error: e.message,
      stack: e.stack
    };
  }
}

// Format failure details for display
function formatFailures(failures, maxShow = 10) {
  if (!failures || failures.length === 0) return '';

  let output = '\n    Failures:\n';
  const toShow = failures.slice(0, maxShow);

  for (const f of toShow) {
    output += `\n      ${f.name}\n`;
    output += `        ${f.error.message.split('\n').join('\n        ')}\n`;
  }

  if (failures.length > maxShow) {
    output += `\n      ... and ${failures.length - maxShow} more failures\n`;
  }

  return output;
}

async function main() {
  console.log(`\n${colors.bold}═══════════════════════════════════════════════════════════════${colors.reset}`);
  console.log(`${colors.bold}  Ruby2JS Selfhost Spec Runner${colors.reset}`);
  console.log(`${colors.bold}═══════════════════════════════════════════════════════════════${colors.reset}\n`);

  let overallSuccess = true;
  const results = {
    ready: [],
    partial: [],
    blocked: []
  };

  // Run "ready" specs - these must pass
  if (manifest.ready.length > 0 && !partialOnly) {
    log('bold', '▶ READY SPECS (must pass):');
    console.log('');

    for (const specName of manifest.ready) {
      process.stdout.write(`  ${specName}: `);

      if (!transpileSpec(specName)) {
        log('red', 'TRANSPILE FAILED');
        overallSuccess = false;
        results.ready.push({ spec: specName, status: 'transpile_failed' });
        continue;
      }

      const result = await runSpec(specName);

      if (result.failed === 0 && !result.error) {
        log('green', `✓ ${result.passed} passed, ${result.skipped} skipped`);
        results.ready.push({ spec: specName, status: 'passed', ...result });
      } else {
        log('red', `✗ ${result.passed} passed, ${result.failed} failed`);
        overallSuccess = false;
        results.ready.push({ spec: specName, status: 'failed', ...result });
        // Always show failure details for ready specs
        if (result.failures && result.failures.length > 0) {
          console.log(colors.red + formatFailures(result.failures) + colors.reset);
        } else if (result.error) {
          console.log(colors.red + `\n    Error: ${result.error}\n` + colors.reset);
        }
      }
    }
    console.log('');
  }

  // Run "partial" specs - report but don't fail CI
  if (manifest.partial.length > 0 && !readyOnly) {
    log('bold', '▶ PARTIAL SPECS (informational, won\'t fail CI):');
    if (!verbose) {
      log('blue', '  (use --verbose to see failure details)');
    }
    console.log('');

    for (const entry of manifest.partial) {
      const specName = typeof entry === 'string' ? entry : entry.spec;
      const reason = typeof entry === 'object' ? entry.reason : '';
      const expectedPass = typeof entry === 'object' ? entry.expected_pass : null;

      process.stdout.write(`  ${specName}: `);

      if (!transpileSpec(specName)) {
        log('yellow', 'TRANSPILE FAILED');
        results.partial.push({ spec: specName, status: 'transpile_failed' });
        continue;
      }

      const result = await runSpec(specName);

      if (result.failed === 0 && !result.error) {
        log('green', `✓ ${result.passed} passed (was partial, now ready!)`);
      } else {
        const status = expectedPass !== null && result.passed >= expectedPass
          ? 'as expected'
          : 'needs work';
        log('yellow', `⚠ ${result.passed} passed, ${result.failed} failed (${status})`);

        // Show failure details in verbose mode
        if (verbose && result.failures && result.failures.length > 0) {
          console.log(colors.yellow + formatFailures(result.failures, 5) + colors.reset);
        } else if (verbose && result.error) {
          console.log(colors.yellow + `\n    Error: ${result.error}\n` + colors.reset);
        }
      }

      if (reason) {
        log('blue', `    Reason: ${reason}`);
      }

      results.partial.push({ spec: specName, status: 'partial', ...result });
    }
    console.log('');
  }

  // Report blocked specs
  const blockedSpecs = Object.entries(manifest.blocked);
  if (blockedSpecs.length > 0 && !readyOnly && !partialOnly) {
    log('bold', `▶ BLOCKED SPECS (${blockedSpecs.length} specs waiting on dependencies):`);
    console.log('');

    // Group by reason
    const byReason = {};
    for (const [spec, reason] of blockedSpecs) {
      if (!byReason[reason]) byReason[reason] = [];
      byReason[reason].push(spec);
    }

    for (const [reason, specs] of Object.entries(byReason)) {
      log('blue', `  ${reason}:`);
      for (const spec of specs) {
        console.log(`    - ${spec}`);
      }
    }
    console.log('');
  }

  // Summary
  console.log(`${colors.bold}═══════════════════════════════════════════════════════════════${colors.reset}`);
  console.log(`${colors.bold}  Summary${colors.reset}`);
  console.log(`${colors.bold}═══════════════════════════════════════════════════════════════${colors.reset}`);

  const readyPassed = results.ready.filter(r => r.status === 'passed').length;
  const partialPassed = results.partial.filter(r => r.failed === 0 && !r.error).length;
  const partialTotal = results.partial.length;

  if (!partialOnly) {
    console.log(`  Ready:   ${readyPassed}/${manifest.ready.length} passed`);
  }
  if (!readyOnly) {
    console.log(`  Partial: ${partialPassed}/${partialTotal} passed (informational)`);
  }
  if (!readyOnly && !partialOnly) {
    console.log(`  Blocked: ${blockedSpecs.length} specs`);
  }
  console.log('');

  // In partial-only mode, always succeed (informational)
  if (partialOnly) {
    log('blue', '  ℹ Partial specs are informational only');
    process.exit(0);
  }

  if (overallSuccess) {
    log('green', '  ✓ All required specs passed!');
  } else {
    log('red', '  ✗ Some required specs failed');
  }
  console.log('');

  process.exit(overallSuccess ? 0 : 1);
}

main().catch(e => {
  console.error(e);
  process.exit(1);
});
