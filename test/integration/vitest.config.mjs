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
  },
  resolve: {
    alias: ruby2jsRailsPath ? {
      // Map ruby2js-rails imports to the available demo's node_modules
      'ruby2js-rails': ruby2jsRailsPath,
    } : {},
  },
  // Treat .erb files as assets (don't try to parse them)
  assetsInclude: ['**/*.erb', '**/*.rb'],
});
