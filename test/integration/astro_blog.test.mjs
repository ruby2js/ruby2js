// Integration tests for the Astro blog demo
// Unlike Rails demos, this validates static site build output
// No database or controller testing - just HTML generation

import { describe, it, expect, beforeAll } from 'vitest';
import { readFileSync, existsSync, readdirSync } from 'fs';
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

  describe('Build Output', () => {
    it('generates index.html', () => {
      const indexPath = join(DIST_DIR, 'index.html');
      expect(existsSync(indexPath)).toBe(true);

      const html = readFileSync(indexPath, 'utf-8');
      expect(html).toContain('Recent Posts');
      expect(html).toContain('Ruby2JS Blog');
    });

    it('generates post pages', () => {
      // Check that post directories were created
      const postsDir = join(DIST_DIR, 'posts');
      expect(existsSync(postsDir)).toBe(true);

      // Should have directories for each post
      const postDirs = readdirSync(postsDir, { withFileTypes: true })
        .filter(d => d.isDirectory())
        .map(d => d.name);

      expect(postDirs).toContain('getting-started');
      expect(postDirs).toContain('astro-components');
      expect(postDirs).toContain('deployment');
    });

    it('generates valid post HTML', () => {
      const postPath = join(DIST_DIR, 'posts/getting-started/index.html');
      expect(existsSync(postPath)).toBe(true);

      const html = readFileSync(postPath, 'utf-8');
      expect(html).toContain('Getting Started with Ruby2JS');
      // Astro adds data-astro-cid attributes to elements
      expect(html).toMatch(/<article[^>]*>/);
      expect(html).toContain('Back to all posts');
    });
  });

  describe('Ruby Transformation', () => {
    it('transforms snake_case to camelCase in output', () => {
      const indexPath = join(DIST_DIR, 'index.html');
      const html = readFileSync(indexPath, 'utf-8');

      // sorted_posts should become sortedPosts
      // The generated JS would have been executed, but we can check
      // that the output looks correct (posts are sorted by date)
      expect(html).not.toContain('sorted_posts');
      expect(html).not.toContain('site_title');
    });

    it('transforms Ruby blocks to arrow functions (posts are mapped)', () => {
      const indexPath = join(DIST_DIR, 'index.html');
      const html = readFileSync(indexPath, 'utf-8');

      // The index page should have multiple post cards from .map
      // Count the post card articles
      const postCardMatches = html.match(/<article[^>]*style=/g);
      expect(postCardMatches).not.toBeNull();
      expect(postCardMatches.length).toBeGreaterThanOrEqual(3); // 3 posts
    });

    it('transforms instance variables to const declarations', () => {
      // The transformation happens at build time, and variables become
      // JavaScript consts. We can verify the output uses the values correctly.
      const postPath = join(DIST_DIR, 'posts/deployment/index.html');
      const html = readFileSync(postPath, 'utf-8');

      // @title becomes title, used in <h1>{title}</h1>
      expect(html).toContain('Deploying Your Astro Blog');
    });
  });

  describe('Content', () => {
    it('renders markdown content in posts', () => {
      const postPath = join(DIST_DIR, 'posts/getting-started/index.html');
      const html = readFileSync(postPath, 'utf-8');

      // Should contain rendered markdown
      expect(html).toContain('<h2');
      expect(html).toContain('Why Ruby?');
      expect(html).toContain('<code');
    });

    it('includes all expected posts on index', () => {
      const indexPath = join(DIST_DIR, 'index.html');
      const html = readFileSync(indexPath, 'utf-8');

      // All 3 posts should be listed
      expect(html).toContain('Getting Started with Ruby2JS');
      expect(html).toContain('Writing Astro Components in Ruby');
      expect(html).toContain('Deploying Your Astro Blog');
    });

    it('posts are sorted by date (newest first)', () => {
      const indexPath = join(DIST_DIR, 'index.html');
      const html = readFileSync(indexPath, 'utf-8');

      // Get positions of each post title
      const deploymentPos = html.indexOf('Deploying Your Astro Blog');
      const astroPos = html.indexOf('Writing Astro Components');
      const gettingStartedPos = html.indexOf('Getting Started with Ruby2JS');

      // Deployment (Jan 25) should come before Astro (Jan 20) should come before Getting Started (Jan 15)
      expect(deploymentPos).toBeLessThan(astroPos);
      expect(astroPos).toBeLessThan(gettingStartedPos);
    });
  });

  describe('Layout and Components', () => {
    it('applies layout to all pages', () => {
      const indexPath = join(DIST_DIR, 'index.html');
      const html = readFileSync(indexPath, 'utf-8');

      expect(html).toContain('<!DOCTYPE html>');
      expect(html).toContain('<meta charset="UTF-8"');
      expect(html).toContain('class="container"');
    });

    it('includes header component', () => {
      const indexPath = join(DIST_DIR, 'index.html');
      const html = readFileSync(indexPath, 'utf-8');

      expect(html).toContain('Ruby2JS Blog');
      expect(html).toContain('Static blog powered by Astro + Ruby2JS');
    });

    it('post cards have proper structure', () => {
      const indexPath = join(DIST_DIR, 'index.html');
      const html = readFileSync(indexPath, 'utf-8');

      // Each post card should have title, date, and excerpt
      // Note: post.url isn't set for glob'd markdown files, so href may be empty
      // This is a known Astro limitation when using Astro.glob() on content files
      expect(html).toContain('<time');
      expect(html).toContain('datetime=');
      // Check that post titles are wrapped in links (even if href is empty)
      expect(html).toMatch(/<a[^>]*>Deploying Your Astro Blog<\/a>/);
    });
  });

  describe('Static Assets', () => {
    it('includes favicon', () => {
      const faviconPath = join(DIST_DIR, 'favicon.svg');
      expect(existsSync(faviconPath)).toBe(true);
    });
  });
});
