import { defineConfig } from 'vitest/config';
import { resolve } from 'path';
import { fileURLToPath } from 'url';
import { existsSync } from 'fs';

const __dirname = fileURLToPath(new URL('.', import.meta.url));

// Find the first available demo's dist for module resolution
const demos = ['blog', 'chat', 'photo_gallery', 'workflow'];
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

// Build aliases object
const aliases = {};
if (ruby2jsRailsPath) {
  aliases['ruby2js-rails'] = ruby2jsRailsPath;
}
// Map absolute imports used by workflow's React components
if (workflowDistPath) {
  aliases['/lib/'] = resolve(workflowDistPath, 'lib') + '/';
  aliases['/app/'] = resolve(workflowDistPath, 'app') + '/';
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
  },
  // Disable sourcemap processing to avoid issues with some generated maps
  build: {
    sourcemap: false,
  },
  resolve: {
    alias: aliases,
  },
  // Treat .erb files as assets (don't try to parse them)
  assetsInclude: ['**/*.erb', '**/*.rb', '**/*.css'],
});
