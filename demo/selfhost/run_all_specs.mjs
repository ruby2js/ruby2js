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

import { execSync, spawnSync } from 'child_process';
import { readFileSync, existsSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const manifest = JSON.parse(readFileSync(join(__dirname, 'spec_manifest.json'), 'utf-8'));
const skipTranspile = process.argv.includes('--skip-transpile');
const readyOnly = process.argv.includes('--ready-only');
const partialOnly = process.argv.includes('--partial-only');

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

function runSpec(specName) {
  const specPath = `./dist/${specName.replace('.rb', '.mjs')}`;

  const result = spawnSync('node', ['run_spec.mjs', specPath], {
    cwd: __dirname,
    stdio: ['pipe', 'pipe', 'pipe'],
    encoding: 'utf-8'
  });

  // Parse output for test counts
  const output = result.stdout + result.stderr;
  const match = output.match(/Tests: (\d+), Passed: (\d+), Failed: (\d+), Skipped: (\d+)/);

  if (match) {
    return {
      total: parseInt(match[1]),
      passed: parseInt(match[2]),
      failed: parseInt(match[3]),
      skipped: parseInt(match[4]),
      exitCode: result.status,
      output
    };
  }

  return {
    total: 0,
    passed: 0,
    failed: 0,
    skipped: 0,
    exitCode: result.status,
    output,
    error: 'Could not parse test output'
  };
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

      const result = runSpec(specName);

      if (result.failed === 0 && !result.error) {
        log('green', `✓ ${result.passed} passed, ${result.skipped} skipped`);
        results.ready.push({ spec: specName, status: 'passed', ...result });
      } else {
        log('red', `✗ ${result.passed} passed, ${result.failed} failed`);
        overallSuccess = false;
        results.ready.push({ spec: specName, status: 'failed', ...result });
        // Show failure details
        const failureMatch = result.output.match(/Failures:[\s\S]*?(?=\n\nTests:|$)/);
        if (failureMatch) {
          console.log(colors.red + failureMatch[0].trim() + colors.reset);
        }
      }
    }
    console.log('');
  }

  // Run "partial" specs - report but don't fail CI
  if (manifest.partial.length > 0 && !readyOnly) {
    log('bold', '▶ PARTIAL SPECS (informational, won\'t fail CI):');
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

      const result = runSpec(specName);

      if (result.failed === 0 && !result.error) {
        log('green', `✓ ${result.passed} passed (was partial, now ready!)`);
      } else {
        const status = expectedPass !== null && result.passed >= expectedPass
          ? 'as expected'
          : 'needs work';
        log('yellow', `⚠ ${result.passed} passed, ${result.failed} failed (${status})`);
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
