import { defineConfig } from 'vite';
import ruby2js from '../src/index.js';

export default defineConfig({
  plugins: [ruby2js()]
});
