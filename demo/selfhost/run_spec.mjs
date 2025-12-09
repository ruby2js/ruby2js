// Run spec tests
import { initPrism, runTests } from './test_harness.mjs';

// Get spec file from command line, default to transliteration_spec
const specFile = process.argv[2] || './dist/transliteration_spec.mjs';

// Initialize Prism parser before running tests
await initPrism();

// Now import and run the specs
await import(specFile);

const success = runTests();
process.exit(success ? 0 : 1);
