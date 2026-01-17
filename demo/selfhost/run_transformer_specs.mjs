#!/usr/bin/env node
// Run transformer specs (Astro, Svelte, Vue component transformers)
// These tests verify the selfhosted JavaScript transformers work correctly.

import { initPrism, runTests, resetTests, getTestResults } from './test_harness.mjs';

// Import transformers and register on Ruby2JS
import { AstroComponentTransformer } from './dist/astro_component_transformer.mjs';
import { SvelteComponentTransformer } from './dist/svelte_component_transformer.mjs';
import { VueComponentTransformer } from './dist/vue_component_transformer.mjs';

// Register on Ruby2JS global so specs can access them
globalThis.Ruby2JS.AstroComponentTransformer = AstroComponentTransformer;
globalThis.Ruby2JS.SvelteComponentTransformer = SvelteComponentTransformer;
globalThis.Ruby2JS.VueComponentTransformer = VueComponentTransformer;

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

async function runTransformerSpec(name, specPath) {
  process.stdout.write(`  ${name}: `);

  try {
    resetTests();
    await import(specPath + '?t=' + Date.now());
    const results = getTestResults();

    if (results.failed === 0) {
      log('green', `✓ ${results.passed} passed, ${results.skipped} skipped`);
      return { success: true, ...results };
    } else {
      log('red', `✗ ${results.passed} passed, ${results.failed} failed`);
      if (results.failures.length > 0) {
        console.log(colors.red + '\n    Failures:' + colors.reset);
        for (const f of results.failures.slice(0, 10)) {
          console.log(colors.red + `\n      ${f.name}` + colors.reset);
          console.log(colors.red + `        ${f.error.message.split('\n').join('\n        ')}` + colors.reset);
        }
        if (results.failures.length > 10) {
          console.log(colors.red + `\n      ... and ${results.failures.length - 10} more failures` + colors.reset);
        }
      }
      return { success: false, ...results };
    }
  } catch (e) {
    log('red', `✗ Error: ${e.message}`);
    console.log(colors.red + e.stack + colors.reset);
    return { success: false, error: e.message };
  }
}

async function main() {
  console.log(`\n${colors.bold}═══════════════════════════════════════════════════════════════${colors.reset}`);
  console.log(`${colors.bold}  Ruby2JS Transformer Spec Runner${colors.reset}`);
  console.log(`${colors.bold}═══════════════════════════════════════════════════════════════${colors.reset}\n`);

  // Initialize Prism
  await initPrism();

  log('bold', '▶ TRANSFORMER SPECS:');
  console.log('');

  const specs = [
    ['Astro Component Transformer', './dist/astro_component_transformer_spec.mjs'],
    ['Svelte Component Transformer', './dist/svelte_component_transformer_spec.mjs'],
    ['Vue Component Transformer', './dist/vue_component_transformer_spec.mjs']
  ];

  let allPassed = true;
  let totalPassed = 0;
  let totalFailed = 0;

  for (const [name, path] of specs) {
    const result = await runTransformerSpec(name, path);
    if (!result.success) allPassed = false;
    totalPassed += result.passed || 0;
    totalFailed += result.failed || 0;
  }

  console.log('');
  console.log(`${colors.bold}═══════════════════════════════════════════════════════════════${colors.reset}`);
  console.log(`${colors.bold}  Summary${colors.reset}`);
  console.log(`${colors.bold}═══════════════════════════════════════════════════════════════${colors.reset}`);
  console.log(`  Total: ${totalPassed} passed, ${totalFailed} failed`);
  console.log('');

  if (allPassed) {
    log('green', '  ✓ All transformer specs passed!');
  } else {
    log('red', '  ✗ Some transformer specs failed');
  }
  console.log('');

  process.exit(allPassed ? 0 : 1);
}

main().catch(e => {
  console.error(e);
  process.exit(1);
});
