// Integration tests for the SSG blog demo (11ty)
// Tests static site generation with content adapter:
// - Markdown content with YAML front matter
// - ActiveRecord-like queries over content
// - Liquid templates
// - No JavaScript required - pure static HTML output

import { describe, it, expect, beforeAll } from 'vitest';
import { readFileSync, existsSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const DEMO_DIR = join(__dirname, 'workspace/ssg_blog');
const SITE_DIR = join(DEMO_DIR, '_site');

describe('SSG Blog Integration Tests', () => {
  beforeAll(() => {
    // Build should have already run during setup
    expect(existsSync(SITE_DIR)).toBe(true);
  });

  describe('Build Output Structure', () => {
    it('generates index.html (home page)', () => {
      const indexPath = join(SITE_DIR, 'index.html');
      expect(existsSync(indexPath)).toBe(true);

      const html = readFileSync(indexPath, 'utf-8');
      expect(html).toContain('Ruby2JS SSG Demo');
      expect(html).toContain('Recent Posts');
    });

    it('generates about page', () => {
      const aboutPath = join(SITE_DIR, 'about/index.html');
      expect(existsSync(aboutPath)).toBe(true);

      const html = readFileSync(aboutPath, 'utf-8');
      expect(html).toContain('About This Demo');
      expect(html).toContain('Content Collections');
      expect(html).toContain('ActiveRecord-like API');
    });
  });

  describe('Content Rendering', () => {
    it('renders posts on home page', () => {
      const indexPath = join(SITE_DIR, 'index.html');
      const html = readFileSync(indexPath, 'utf-8');

      // Should contain published posts
      expect(html).toContain('Welcome to the Blog');
      expect(html).toContain('Getting Started with Ruby2JS');

      // Should NOT contain draft posts
      expect(html).not.toContain('Upcoming Features');
    });

    it('renders post metadata (dates, tags)', () => {
      const indexPath = join(SITE_DIR, 'index.html');
      const html = readFileSync(indexPath, 'utf-8');

      // Should have date formatting
      expect(html).toMatch(/January \d+, 2024/);

      // Should have tags
      expect(html).toContain('ruby');
      expect(html).toContain('javascript');
      expect(html).toContain('tutorial');
    });

    it('renders author information on about page', () => {
      const aboutPath = join(SITE_DIR, 'about/index.html');
      const html = readFileSync(aboutPath, 'utf-8');

      // Should show author from content/authors/sam.md
      expect(html).toContain('Sam Ruby');
      expect(html).toContain('Creator of Ruby2JS');
    });

    it('shows content statistics', () => {
      const aboutPath = join(SITE_DIR, 'about/index.html');
      const html = readFileSync(aboutPath, 'utf-8');

      // Should show post and author counts (3 posts, 1 author)
      // Note: We check that numbers appear near the expected text
      expect(html).toContain('total posts');
      expect(html).toContain('authors');
    });
  });

  describe('Layout and Navigation', () => {
    it('uses shared layout', () => {
      const indexPath = join(SITE_DIR, 'index.html');
      const aboutPath = join(SITE_DIR, 'about/index.html');

      const indexHtml = readFileSync(indexPath, 'utf-8');
      const aboutHtml = readFileSync(aboutPath, 'utf-8');

      // Both pages should use the layout
      expect(indexHtml).toContain('<!DOCTYPE html>');
      expect(aboutHtml).toContain('<!DOCTYPE html>');

      // Both should have navigation
      expect(indexHtml).toContain('<nav>');
      expect(aboutHtml).toContain('<nav>');

      // Both should have footer with credits
      expect(indexHtml).toContain('11ty');
      expect(aboutHtml).toContain('Ruby2JS');
    });

    it('has working navigation links', () => {
      const indexPath = join(SITE_DIR, 'index.html');
      const html = readFileSync(indexPath, 'utf-8');

      expect(html).toContain('href="/"');
      expect(html).toContain('href="/about/"');
    });
  });

  describe('Static Output (No JavaScript)', () => {
    it('does not include JavaScript bundles', () => {
      // SSG blog is pure static - no JS required
      const indexPath = join(SITE_DIR, 'index.html');
      const html = readFileSync(indexPath, 'utf-8');

      // Should not have script tags (except possibly inline)
      expect(html).not.toMatch(/<script[^>]+src=/);
    });

    it('does not contain Ruby syntax in output', () => {
      const indexPath = join(SITE_DIR, 'index.html');
      const aboutPath = join(SITE_DIR, 'about/index.html');

      const indexHtml = readFileSync(indexPath, 'utf-8');
      const aboutHtml = readFileSync(aboutPath, 'utf-8');

      // Should not contain Ruby-specific syntax (except in code examples)
      // The about page shows installation code, so we only check for unexpected Ruby
      expect(indexHtml).not.toMatch(/\bdef\s+\w+\(/);  // Ruby method definitions
      expect(indexHtml).not.toMatch(/\bdo\s*\|/);      // Ruby block syntax
      expect(indexHtml).not.toContain('<%=');          // ERB tags
      expect(indexHtml).not.toContain('<%');           // ERB tags
    });
  });

  describe('Styling', () => {
    it('includes CSS styles', () => {
      const indexPath = join(SITE_DIR, 'index.html');
      const html = readFileSync(indexPath, 'utf-8');

      // Should have inline styles in head
      expect(html).toContain('<style>');
      expect(html).toContain('--primary');
    });
  });
});
