import { defineConfig } from 'vite';
import { juntos } from 'ruby2js-rails/vite';

export default defineConfig({
  plugins: juntos({
    appRoot: '..'  // Source files are in parent directory
  })
});
