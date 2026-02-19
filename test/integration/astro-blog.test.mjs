// Integration tests for the Astro blog demo (Phase 6)
// Tests the three-level architecture:
// - Level 1: Static markdown (about page)
// - Level 2: Astro pages (.astro.rb)
// - Level 3: React islands (.jsx.rb)
//
// Note: Posts are stored in IndexedDB (client-side), so we can't test
// post content at build time. We verify structure and island inclusion.

import { describe, it, expect, beforeAll } from 'vitest';
import { readFileSync, existsSync, readdirSync, globSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const DEMO_DIR = join(__dirname, 'workspace/astro_blog');
const DIST_DIR = join(DEMO_DIR, 'dist');

describe('Astro Blog Integration Tests', () => {
  beforeAll(() => {
    // Build should have already run during setup
    expect(existsSync(DIST_DIR)).toBe(true);
  });

  describe('Build Output Structure', () => {
    it('generates index.html (landing page)', () => {
      const indexPath = join(DIST_DIR, 'index.html');
      expect(existsSync(indexPath)).toBe(true);

      const html = readFileSync(indexPath, 'utf-8');
      expect(html).toContain('Welcome to the Astro Blog');
      expect(html).toContain('Three Levels of Ruby');
    });

    it('generates about page (Level 1 - markdown)', () => {
      const aboutPath = join(DIST_DIR, 'about/index.html');
      expect(existsSync(aboutPath)).toBe(true);

      const html = readFileSync(aboutPath, 'utf-8');
      expect(html).toContain('About This Blog');
      expect(html).toContain('Static content');
      expect(html).toContain('IndexedDB');
    });

    it('generates posts index page (Level 2 - hosts islands)', () => {
      const postsPath = join(DIST_DIR, 'posts/index.html');
      expect(existsSync(postsPath)).toBe(true);

      const html = readFileSync(postsPath, 'utf-8');
      expect(html).toContain('Blog Posts');
      expect(html).toContain('Create New Post');
    });

    it('generates static assets', () => {
      const faviconPath = join(DIST_DIR, 'favicon.svg');
      expect(existsSync(faviconPath)).toBe(true);
    });
  });

  describe('React Islands (Level 3)', () => {
    it('includes PostList island with client:load hydration', () => {
      const postsPath = join(DIST_DIR, 'posts/index.html');
      const html = readFileSync(postsPath, 'utf-8');

      // Astro adds astro-island elements for hydrated components
      expect(html).toContain('astro-island');
      // client:load adds specific hydration markers
      expect(html).toMatch(/client="load"/);
    });

    it('includes PostForm island with client:load hydration', () => {
      const postsPath = join(DIST_DIR, 'posts/index.html');
      const html = readFileSync(postsPath, 'utf-8');

      // Should have multiple islands (PostList and PostForm)
      const islandMatches = html.match(/astro-island/g);
      expect(islandMatches).not.toBeNull();
      expect(islandMatches.length).toBeGreaterThanOrEqual(2);
    });

    it('transpiled .jsx.rb files to valid JavaScript', () => {
      // Check that JS bundles were created
      const jsFiles = globSync(join(DIST_DIR, '_astro/*.js'));
      expect(jsFiles.length).toBeGreaterThan(0);

      // Check that at least one bundle contains React-related code
      // (either direct references or minified equivalents)
      let hasReactCode = false;
      for (const file of jsFiles) {
        const content = readFileSync(file, 'utf-8');
        // Look for signs of transpiled JSX/React code
        if (content.includes('useState') ||
            content.includes('useEffect') ||
            content.includes('createElement') ||
            content.includes('react')) {
          hasReactCode = true;
          break;
        }
      }
      expect(hasReactCode).toBe(true);
    });

    it('does not contain Ruby syntax in bundled JS', () => {
      const jsFiles = globSync(join(DIST_DIR, '_astro/*.js'));

      for (const file of jsFiles) {
        const content = readFileSync(file, 'utf-8');
        // Should not contain Ruby-specific syntax
        expect(content).not.toMatch(/\bdef\s+\w+\(/);  // Ruby method definitions
        expect(content).not.toMatch(/\bdo\s*\|/);      // Ruby block syntax
        expect(content).not.toContain('__END__');       // Ruby template separator
      }
    });
  });

  describe('View Transitions', () => {
    it('includes ViewTransitions in layout', () => {
      const indexPath = join(DIST_DIR, 'index.html');
      const html = readFileSync(indexPath, 'utf-8');

      // Astro View Transitions add specific meta tags and scripts
      expect(html).toMatch(/view-transition|astro:transitions/i);
    });

    it('all pages use the shared layout', () => {
      const pages = [
        join(DIST_DIR, 'index.html'),
        join(DIST_DIR, 'about/index.html'),
        join(DIST_DIR, 'posts/index.html')
      ];

      for (const pagePath of pages) {
        const html = readFileSync(pagePath, 'utf-8');
        expect(html).toContain('<!DOCTYPE html>');
        // Astro adds data-astro-cid attributes for CSS scoping
        expect(html).toMatch(/<nav[^>]*>/);
        expect(html).toContain('Home');
        expect(html).toContain('Posts');
        expect(html).toContain('About');
      }
    });
  });

  describe('Ruby Transformation (.astro.rb)', () => {
    it('transforms instance variables to const declarations', () => {
      // The landing page uses @title = "Astro Blog with Ruby2JS"
      // This should be transformed to const title = ...
      const indexPath = join(DIST_DIR, 'index.html');
      const html = readFileSync(indexPath, 'utf-8');

      // The title should appear in the <title> tag
      expect(html).toContain('<title>Astro Blog with Ruby2JS</title>');
    });

    it('transforms snake_case to camelCase', () => {
      // Check that no snake_case remains in output
      const indexPath = join(DIST_DIR, 'index.html');
      const html = readFileSync(indexPath, 'utf-8');

      // Should not contain common Ruby snake_case patterns
      expect(html).not.toContain('post_card');
      expect(html).not.toContain('site_title');
      expect(html).not.toContain('sorted_posts');
    });

    it('renders Astro.props correctly', () => {
      // The layout uses Astro.props[:title]
      // Different pages should have different titles
      const aboutPath = join(DIST_DIR, 'about/index.html');
      const postsPath = join(DIST_DIR, 'posts/index.html');

      const aboutHtml = readFileSync(aboutPath, 'utf-8');
      const postsHtml = readFileSync(postsPath, 'utf-8');

      expect(aboutHtml).toContain('<title>About</title>');
      expect(postsHtml).toContain('<title>Blog Posts</title>');
    });
  });

  describe('Navigation', () => {
    it('has working navigation links', () => {
      const indexPath = join(DIST_DIR, 'index.html');
      const html = readFileSync(indexPath, 'utf-8');

      // Links use import.meta.env.BASE_URL; without --base, BASE_URL is "/"
      expect(html).toContain('Home');
      expect(html).toContain('Posts');
      expect(html).toContain('About');
      expect(html).toMatch(/href="[^"]*"/);  // has href attributes
    });

    it('posts page has navigation', () => {
      const postsPath = join(DIST_DIR, 'posts/index.html');
      const html = readFileSync(postsPath, 'utf-8');

      expect(html).toContain('About');
    });
  });

  describe('Styling', () => {
    it('includes CSS styles in output', () => {
      const indexPath = join(DIST_DIR, 'index.html');
      const html = readFileSync(indexPath, 'utf-8');

      // Should have either inline styles or linked CSS
      expect(html).toMatch(/<style|\.css/);

      // Should include CSS custom properties from layout
      expect(html).toContain('--color-primary');
    });
  });
});
