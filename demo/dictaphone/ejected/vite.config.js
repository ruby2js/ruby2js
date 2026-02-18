import { defineConfig } from 'vite';

export default defineConfig({
  // Ejected JavaScript - no ruby2js transformation needed
  resolve: {
    alias: {
      'app/': './app/',
      'config/': './config/',
      'db/': './db/'
    }
  }
});
