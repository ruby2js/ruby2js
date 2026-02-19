import { defineConfig } from 'vitest/config';
import { resolve } from 'path';
import { fileURLToPath } from 'url';
import { existsSync } from 'fs';

const __dirname = fileURLToPath(new URL('.', import.meta.url));

// Find the first available demo's dist for module resolution
const demos = ['blog', 'chat', 'photo_gallery', 'workflow', 'notes'];
let juntosPath = null;
let workflowDistPath = null;

for (const demo of demos) {
  const distPath = resolve(__dirname, `workspace/${demo}/dist`);
  const candidatePath = resolve(distPath, 'node_modules/juntos');
  if (existsSync(candidatePath)) {
    juntosPath = juntosPath || candidatePath;
    if (demo === 'workflow') {
      workflowDistPath = distPath;
    }
  }
}

// Fallback to packages directory for juntos (local development)
if (!juntosPath) {
  const packagePath = resolve(__dirname, '../../packages/juntos');
  if (existsSync(packagePath)) {
    juntosPath = packagePath;
  }
}

// Build aliases - use array format for regex-based aliases
const aliases = [];

// Ensure all React imports use the same instance (fixes hooks errors)
// When RBX components bundle their own React, we need to redirect to test's React
const reactPath = resolve(__dirname, 'node_modules/react');
const reactDomPath = resolve(__dirname, 'node_modules/react-dom');
aliases.push({ find: 'react', replacement: reactPath });
aliases.push({ find: 'react-dom', replacement: reactDomPath });

if (juntosPath) {
  // Match juntos subpath imports and map to package directory
  aliases.push({
    find: /^juntos\/(.*)$/,
    replacement: resolve(juntosPath, '$1'),
  });
  aliases.push({
    find: 'juntos',
    replacement: juntosPath,
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
