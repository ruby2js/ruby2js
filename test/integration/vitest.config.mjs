import { defineConfig } from 'vitest/config';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';
import { existsSync } from 'fs';

const __dirname = fileURLToPath(new URL('.', import.meta.url));

// Find the first available demo's dist for module resolution
// Each demo has ruby2js-rails installed in its dist/node_modules
const demos = ['blog', 'chat', 'photo_gallery', 'workflow'];
let ruby2jsRailsPath = null;

for (const demo of demos) {
  const candidatePath = resolve(__dirname, `workspace/${demo}/dist/node_modules/ruby2js-rails`);
  if (existsSync(candidatePath)) {
    ruby2jsRailsPath = candidatePath;
    break;
  }
}

export default defineConfig({
  test: {
    globals: true,
    testTimeout: 30000,
    hookTimeout: 30000,
    // Mock CSS imports (for React Flow in workflow demo)
    css: false,
  },
  // Disable sourcemap processing to avoid issues with some generated maps
  build: {
    sourcemap: false,
  },
  resolve: {
    alias: ruby2jsRailsPath ? {
      // Map ruby2js-rails imports to the available demo's node_modules
      'ruby2js-rails': ruby2jsRailsPath,
    } : {},
  },
  // Treat .erb files as assets (don't try to parse them)
  assetsInclude: ['**/*.erb', '**/*.rb', '**/*.css'],
  // SSR options for workflow demo's React dependencies
  ssr: {
    // Don't try to externalize React/ReactFlow (let Vite handle them)
    noExternal: ['react', 'react-dom', 'reactflow'],
  },
});
