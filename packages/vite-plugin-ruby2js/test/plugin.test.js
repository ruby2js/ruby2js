/**
 * Basic tests for vite-plugin-ruby2js
 *
 * Run with: node --test test/plugin.test.js
 */

import { test, describe } from 'node:test';
import assert from 'node:assert';
import ruby2js from '../src/index.js';
import { rails } from '../src/presets/rails.js';

describe('vite-plugin-ruby2js', () => {
  test('creates plugin with default options', () => {
    const plugin = ruby2js();

    assert.strictEqual(plugin.name, 'vite-plugin-ruby2js');
    assert.strictEqual(typeof plugin.transform, 'function');
  });

  test('ignores non-Ruby files', async () => {
    const plugin = ruby2js();

    const result = await plugin.transform('const x = 1;', 'test.js');
    assert.strictEqual(result, null);
  });

  test('transforms Ruby files', async () => {
    const plugin = ruby2js();

    const ruby = `
def greet(name)
  "Hello, #{name}!"
end
`;

    const result = await plugin.transform(ruby, 'test.rb');

    assert.ok(result, 'should return a result');
    assert.ok(result.code, 'should have code');
    assert.ok(result.code.includes('function greet'), 'should contain function');
  });

  test('generates source maps', async () => {
    const plugin = ruby2js();

    const ruby = 'x = 1';
    const result = await plugin.transform(ruby, 'test.rb');

    assert.ok(result.map, 'should have source map');
    assert.strictEqual(result.map.version, 3, 'should be source map v3');
    assert.ok(result.map.sources.includes('test.rb'), 'should reference source file');
  });

  test('respects exclude patterns', async () => {
    const plugin = ruby2js({ exclude: ['vendor'] });

    const result = await plugin.transform('x = 1', 'vendor/lib.rb');
    assert.strictEqual(result, null, 'should exclude vendor files');
  });

  test('applies custom filters', async () => {
    const plugin = ruby2js({
      filters: ['functions', 'esm']
    });

    const ruby = `
export def double(x)
  x * 2
end
`;

    const result = await plugin.transform(ruby, 'math.rb');
    assert.ok(result.code.includes('export'), 'should have ESM export');
  });
});

describe('rails preset', () => {
  test('creates array of plugins', () => {
    const plugins = rails();

    assert.ok(Array.isArray(plugins), 'should return array');
    assert.ok(plugins.length >= 2, 'should have multiple plugins');
  });

  test('includes core ruby2js plugin', () => {
    const plugins = rails();
    const corePlugin = plugins.find(p => p.name === 'vite-plugin-ruby2js');

    assert.ok(corePlugin, 'should include core plugin');
  });

  test('includes config plugin with aliases', () => {
    const plugins = rails();
    const configPlugin = plugins.find(p => p.name === 'ruby2js-rails-config');

    assert.ok(configPlugin, 'should include config plugin');

    const config = configPlugin.config();
    assert.ok(config.resolve.alias['@controllers'], 'should have @controllers alias');
  });

  test('includes HMR plugin by default', () => {
    const plugins = rails();
    const hmrPlugin = plugins.find(p => p.name === 'ruby2js-rails-hmr');

    assert.ok(hmrPlugin, 'should include HMR plugin');
    assert.ok(typeof hmrPlugin.handleHotUpdate, 'function', 'should have handleHotUpdate');
  });

  test('can disable HMR', () => {
    const plugins = rails({ hmr: false });
    const hmrPlugin = plugins.find(p => p.name === 'ruby2js-rails-hmr');

    assert.strictEqual(hmrPlugin, undefined, 'should not include HMR plugin');
  });

  test('accepts custom aliases', () => {
    const plugins = rails({
      aliases: { '@custom': 'app/custom' }
    });
    const configPlugin = plugins.find(p => p.name === 'ruby2js-rails-config');

    const config = configPlugin.config();
    assert.strictEqual(config.resolve.alias['@custom'], 'app/custom');
  });
});
