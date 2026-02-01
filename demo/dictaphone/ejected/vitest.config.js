import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
    include: ['test/**/*.test.mjs', 'test/**/*.test.js'],
    setupFiles: ['./test/setup.mjs']
  }
});
