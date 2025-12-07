// Run the transliteration spec
import './dist/transliteration_spec.mjs';
import { runTests } from './test_harness.mjs';

const success = runTests();
process.exit(success ? 0 : 1);
