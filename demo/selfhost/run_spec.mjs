// Run the transliteration spec
import { initPrism, runTests } from './test_harness.mjs';

// Initialize Prism parser before running tests
await initPrism();

// Now import and run the specs
await import('./dist/transliteration_spec.mjs');

const success = runTests();
process.exit(success ? 0 : 1);
