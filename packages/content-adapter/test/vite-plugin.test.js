import { test, describe } from 'node:test';
import assert from 'node:assert';
import path from 'path';
import { fileURLToPath } from 'url';
import contentAdapter from '../src/vite.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const fixturesDir = path.join(__dirname, 'fixtures', 'content');

describe('Vite plugin', () => {
  const plugin = contentAdapter({ dir: fixturesDir });

  // Simulate Vite's configResolved
  plugin.configResolved({ root: __dirname });

  test('resolves virtual:content module ID', () => {
    const resolved = plugin.resolveId('virtual:content');
    assert.strictEqual(resolved, '\0virtual:content');
  });

  test('does not resolve other module IDs', () => {
    const resolved = plugin.resolveId('some-other-module');
    assert.strictEqual(resolved, undefined);
  });

  test('loads virtual module with collections', () => {
    const code = plugin.load('\0virtual:content');
    assert.ok(code.includes("import { createCollection } from '@ruby2js/content-adapter'"));
    assert.ok(code.includes('export const Post = createCollection'));
    assert.ok(code.includes('export const Author = createCollection'));
  });

  test('parses front matter correctly', () => {
    const code = plugin.load('\0virtual:content');
    assert.ok(code.includes('"title": "Hello World"'));
    assert.ok(code.includes('"author": "alice"'));
    assert.ok(code.includes('"draft": false'));
  });

  test('extracts slug from filename', () => {
    const code = plugin.load('\0virtual:content');
    // 2024-01-01-hello-world.md -> slug: "hello-world"
    assert.ok(code.includes('"slug": "hello-world"'));
    assert.ok(code.includes('"slug": "getting-started"'));
  });

  test('renders markdown body to HTML', () => {
    const code = plugin.load('\0virtual:content');
    assert.ok(code.includes('<p>This is my first post'));
    assert.ok(code.includes('<h2'));  // ## Installation becomes <h2>
  });

  test('infers belongsTo relationship', () => {
    const code = plugin.load('\0virtual:content');
    // Post has 'author' attribute, 'authors' collection exists
    assert.ok(code.includes("Post.belongsTo('author', Author)"));
  });
});

describe('Generated module execution', async () => {
  const plugin = contentAdapter({ dir: fixturesDir });
  plugin.configResolved({ root: __dirname });

  test('generated code is valid JavaScript', async () => {
    const code = plugin.load('\0virtual:content');

    // Replace the import with actual module
    const testCode = code.replace(
      "import { createCollection } from '@ruby2js/content-adapter';",
      `import { createCollection } from '${path.join(__dirname, '..', 'src', 'index.js')}';`
    );

    // Write to temp file and import
    const fs = await import('fs');
    const tempFile = path.join(__dirname, '.temp-generated.mjs');
    fs.writeFileSync(tempFile, testCode);

    try {
      const module = await import(tempFile);

      // Verify collections exist
      assert.ok(module.Post);
      assert.ok(module.Author);

      // Verify query API works
      const posts = module.Post.toArray();
      assert.strictEqual(posts.length, 3);

      // Verify filtering works
      const published = module.Post.where({ draft: false }).toArray();
      assert.strictEqual(published.length, 2);

      // Verify relationship works
      const post = module.Post.find('hello-world');
      assert.ok(post);
      assert.strictEqual(post.author.name, 'Alice Smith');
    } finally {
      fs.unlinkSync(tempFile);
    }
  });
});
