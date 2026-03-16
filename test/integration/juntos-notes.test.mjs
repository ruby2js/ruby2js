// Integration tests for the notes demo
// Runs the demo's own test suite using Vitest
//
// The demo contains:
// - app/models/*.rb - Model definitions with validations
// - app/controllers/*.rb - Controller actions
// - test/*.test.mjs - Vitest tests that exercise the above
//
// The Vite plugin transforms .rb files on-the-fly during test runs.

import { describe, it, expect, beforeAll } from 'vitest';
import { execSync } from 'child_process';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { existsSync } from 'fs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const DEMO_DIR = join(__dirname, 'workspace/notes');

describe('Notes Demo Integration Tests', () => {
  beforeAll(() => {
    // Verify the demo exists
    if (!existsSync(DEMO_DIR)) {
      throw new Error(`Demo not found at ${DEMO_DIR}. Run: node setup.mjs notes`);
    }

    // Verify test files exist
    if (!existsSync(join(DEMO_DIR, 'test/notes.test.mjs'))) {
      throw new Error('Test files not found. The demo may need to be regenerated.');
    }
  });

  it('runs the demo test suite successfully', () => {
    // Run npm test in the demo directory
    // This executes vitest which transforms .rb files on-the-fly
    try {
      const output = execSync('JUNTOS_DATABASE=sqlite npm test', {
        cwd: DEMO_DIR,
        encoding: 'utf-8',
        stdio: ['pipe', 'pipe', 'pipe'],
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
      execSync('npx juntos build -d sqlite -t node', {
        cwd: DEMO_DIR,
        encoding: 'utf-8',
        stdio: ['pipe', 'pipe', 'pipe']
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
