import { defineConfig } from 'vitest/config';
import { resolve } from 'path';
import { fileURLToPath } from 'url';
import { existsSync } from 'fs';

const __dirname = fileURLToPath(new URL('.', import.meta.url));

// Find the first available demo's dist for module resolution
const demos = ['blog', 'chat', 'photo_gallery', 'workflow', 'notes'];
let ruby2jsRailsPath = null;
let workflowDistPath = null;

for (const demo of demos) {
  const distPath = resolve(__dirname, `workspace/${demo}/dist`);
  const candidatePath = resolve(distPath, 'node_modules/ruby2js-rails');
  if (existsSync(candidatePath)) {
    ruby2jsRailsPath = ruby2jsRailsPath || candidatePath;
    if (demo === 'workflow') {
      workflowDistPath = distPath;
    }
  }
}

// Fallback to packages directory for ruby2js-rails (local development)
if (!ruby2jsRailsPath) {
  const packagePath = resolve(__dirname, '../../packages/ruby2js-rails');
  if (existsSync(packagePath)) {
    ruby2jsRailsPath = packagePath;
  }
}

// Build aliases - use array format for regex-based aliases
const aliases = [];
if (ruby2jsRailsPath) {
  // Match ruby2js-rails subpath imports and map to package directory
  aliases.push({
    find: /^ruby2js-rails\/(.*)$/,
    replacement: resolve(ruby2jsRailsPath, '$1'),
  });
  aliases.push({
    find: 'ruby2js-rails',
    replacement: ruby2jsRailsPath,
  });
}
// Map absolute imports used by workflow's React components
if (workflowDistPath) {
  aliases.push({ find: /^\/lib\/(.*)$/, replacement: resolve(workflowDistPath, 'lib/$1') });
  aliases.push({ find: /^\/app\/(.*)$/, replacement: resolve(workflowDistPath, 'app/$1') });
}

export default defineConfig({
  test: {
    globals: true,
    testTimeout: 30000,
    hookTimeout: 30000,
    // Use jsdom for React component testing (workflow demo)
    environment: 'jsdom',
    // Mock CSS imports (for React Flow in workflow demo)
    css: false,
    // notes.test.mjs uses @vitest-environment node directive
  },
  resolve: {
    alias: aliases,
  },
  // Treat .erb files as assets (don't try to parse them)
  assetsInclude: ['**/*.erb', '**/*.rb', '**/*.css'],
  ssr: {
    // Don't try to transform native modules
    external: ['better-sqlite3'],
  },
});
