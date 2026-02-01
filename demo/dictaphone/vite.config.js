import { defineConfig } from 'vite';
import { juntos } from 'ruby2js-rails/vite';

export default defineConfig({
  plugins: juntos()
});
