// Integration tests for the blog demo
// Runs the demo's own test suite using Vitest
//
// The demo contains:
// - app/models/*.rb - Model definitions with validations and associations
// - app/controllers/*.rb - Controller actions
// - test/models/*_test.rb - Model tests (transpiled to .test.mjs by juntos test)
// - test/controllers/*_test.rb - Controller tests (transpiled to .test.mjs by juntos test)
//
// `juntos test` transpiles Ruby test files to .test.mjs, then runs Vitest.
// The Vite plugin transforms app .rb files on-the-fly during test runs.

import { describe, it, expect, beforeAll } from 'vitest';
import { execSync } from 'child_process';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { existsSync } from 'fs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const DEMO_DIR = join(__dirname, 'workspace/blog');

describe('Blog Demo Integration Tests', () => {
  beforeAll(() => {
    // Verify the demo exists
    if (!existsSync(DEMO_DIR)) {
      throw new Error(`Demo not found at ${DEMO_DIR}. Run: node setup.mjs blog`);
    }

    // Verify Ruby test files exist (these get transpiled to .test.mjs by juntos test)
    const hasModelTests = existsSync(join(DEMO_DIR, 'test/models'));
    const hasControllerTests = existsSync(join(DEMO_DIR, 'test/controllers'));
    if (!hasModelTests && !hasControllerTests) {
      throw new Error('Test files not found. The demo may need to be regenerated.');
    }
  });

  it('runs the demo test suite successfully', () => {
    // Run juntos test which transpiles Ruby test files then runs vitest
    try {
      const output = execSync('npx juntos test -d sqlite', {
        cwd: DEMO_DIR,
        encoding: 'utf-8',
        stdio: ['pipe', 'pipe', 'pipe'],
        timeout: 120000,
        env: {
          ...process.env,
          JUNTOS_DATABASE: 'sqlite',
          JUNTOS_TARGET: 'node'
        }
      });

      console.log('Test output:', output);
      expect(output).toContain('pass');
    } catch (error) {
      // If tests fail, show the output for debugging
      if (error.stdout) {
        console.log('stdout:', error.stdout);
      }
      if (error.stderr) {
        console.log('stderr:', error.stderr);
      }
      throw new Error(`Demo tests failed: ${error.message}`);
    }
  });

  it('can build the demo with Vite', () => {
    // Verify the build pipeline works
    try {
      execSync('JUNTOS_DATABASE=sqlite JUNTOS_TARGET=node npm run build', {
        cwd: DEMO_DIR,
        encoding: 'utf-8',
        stdio: ['pipe', 'pipe', 'pipe'],
        env: {
          ...process.env,
          JUNTOS_DATABASE: 'sqlite',
          JUNTOS_TARGET: 'node'
        }
      });

      // Verify dist was created
      expect(existsSync(join(DEMO_DIR, 'dist'))).toBe(true);
    } catch (error) {
      if (error.stdout) console.log('stdout:', error.stdout);
      if (error.stderr) console.log('stderr:', error.stderr);
      throw new Error(`Build failed: ${error.message}`);
    }
  });
});
