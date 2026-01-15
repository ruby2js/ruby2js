import { test, describe, before, after } from 'node:test';
import assert from 'node:assert';
import * as esbuild from 'esbuild';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import ruby2js from '../src/index.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const fixturesDir = path.join(__dirname, 'fixtures');

describe('esbuild-plugin-ruby2js', async () => {
  // Setup before tests
  before(async () => {
    await fs.promises.mkdir(fixturesDir, { recursive: true });

    await fs.promises.writeFile(
      path.join(fixturesDir, 'simple.rb'),
      `def greet(name)
  puts "Hello, \#{name}!"
end
`
    );

    await fs.promises.writeFile(
      path.join(fixturesDir, 'math.rb'),
      `def add(a, b)
  a + b
end

def multiply(a, b)
  a * b
end
`
    );

    await fs.promises.writeFile(
      path.join(fixturesDir, 'with_export.rb'),
      `def hello
  "world"
end

export default :hello
`
    );
  });

  // Cleanup after tests
  after(async () => {
    await fs.promises.rm(fixturesDir, { recursive: true, force: true });
  });

  test('transforms Ruby file with autoexports', async () => {
    const result = await esbuild.build({
      entryPoints: [path.join(fixturesDir, 'simple.rb')],
      plugins: [ruby2js({ autoexports: true })],
      bundle: true,
      write: false,
      format: 'esm'
    });

    const output = result.outputFiles[0].text;
    assert.ok(output.includes('greet'), 'should contain greet function');
    assert.ok(output.includes('console.log'), 'should convert puts to console.log');
  });

  test('transforms multiple functions', async () => {
    const result = await esbuild.build({
      entryPoints: [path.join(fixturesDir, 'math.rb')],
      plugins: [ruby2js({ autoexports: true })],
      bundle: true,
      write: false,
      format: 'esm'
    });

    const output = result.outputFiles[0].text;
    assert.ok(output.includes('add'), 'should contain add function');
    assert.ok(output.includes('multiply'), 'should contain multiply function');
  });

  test('handles export default', async () => {
    const result = await esbuild.build({
      entryPoints: [path.join(fixturesDir, 'with_export.rb')],
      plugins: [ruby2js()],
      bundle: true,
      write: false,
      format: 'esm'
    });

    const output = result.outputFiles[0].text;
    assert.ok(output.includes('hello'), 'should contain hello function');
    assert.ok(output.includes('default'), 'should have default export');
  });

  test('respects eslevel option', async () => {
    const result = await esbuild.build({
      entryPoints: [path.join(fixturesDir, 'simple.rb')],
      plugins: [ruby2js({ eslevel: 2020, autoexports: true })],
      bundle: true,
      write: false,
      format: 'esm'
    });

    const output = result.outputFiles[0].text;
    assert.ok(output.includes('greet'), 'should still produce valid output');
  });

  test('applies custom filters', async () => {
    const result = await esbuild.build({
      entryPoints: [path.join(fixturesDir, 'simple.rb')],
      plugins: [ruby2js({ filters: ['Functions', 'ESM'], autoexports: true })],
      bundle: true,
      write: false,
      format: 'esm'
    });

    const output = result.outputFiles[0].text;
    assert.ok(output.includes('greet'), 'should transform with custom filters');
  });

  test('works without bundling', async () => {
    const result = await esbuild.build({
      entryPoints: [path.join(fixturesDir, 'simple.rb')],
      plugins: [ruby2js()],
      bundle: false,
      write: false,
      format: 'esm'
    });

    const output = result.outputFiles[0].text;
    assert.ok(output.includes('greet'), 'should contain greet function');
  });

  test('reports syntax errors', async () => {
    const badFile = path.join(fixturesDir, 'bad.rb');
    await fs.promises.writeFile(badFile, 'def foo(\n');

    try {
      await esbuild.build({
        entryPoints: [badFile],
        plugins: [ruby2js()],
        bundle: true,
        write: false
      });
      assert.fail('should have thrown an error');
    } catch (err) {
      assert.ok(err.errors?.length > 0, 'should have error details');
    }
  });
});
