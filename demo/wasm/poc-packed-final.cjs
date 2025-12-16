// Node.js proof of concept for Ruby2JS + pre-built ruby.wasm (packed)
const fs = require('fs');
const { WASI } = require('wasi');
const { RubyVM } = require('@ruby/wasm-wasi');

const wasmFile = process.argv[2] || './ruby2js-packed-final.wasm';

console.log(`Loading ${wasmFile}...`);
const startTime = performance.now();

async function main() {
  try {
    // Read the WASM file
    const wasmBuffer = fs.readFileSync(wasmFile);
    console.log(`  File read: ${((performance.now() - startTime) / 1000).toFixed(2)}s (${(wasmBuffer.length / 1024 / 1024).toFixed(1)} MB)`);

    // Compile the WASM module
    const module = await WebAssembly.compile(wasmBuffer);
    console.log(`  WASM compiled: ${((performance.now() - startTime) / 1000).toFixed(2)}s`);

    // Initialize WASI
    const wasi = new WASI({
      version: 'preview1',
    });

    // Initialize the Ruby VM
    const vm = new RubyVM();
    const imports = {
      wasi_snapshot_preview1: wasi.wasiImport,
    };
    vm.addToImports(imports);

    const instance = await WebAssembly.instantiate(module, imports);
    await vm.setInstance(instance);
    wasi.initialize(instance);
    vm.initialize();
    console.log(`  Ruby VM initialized: ${((performance.now() - startTime) / 1000).toFixed(2)}s`);

    // Test Ruby version
    console.log('\n=== Step 1: Ruby Environment ===');
    const rubyVersion = vm.eval('RUBY_VERSION').toString();
    console.log(`Ruby version: ${rubyVersion}`);

    const platform = vm.eval('RUBY_PLATFORM').toString();
    console.log(`Platform: ${platform}`);

    const hasPrism = vm.eval(`defined?(Prism) ? 'yes' : 'no'`).toString();
    console.log(`Prism available: ${hasPrism}`);

    // Check load path
    const loadPath = vm.eval('$LOAD_PATH.inspect').toString();
    console.log(`Load path: ${loadPath}`);

    // Load Ruby2JS
    console.log('\n=== Step 2: Load Ruby2JS ===');
    vm.eval(`
      $LOAD_PATH.unshift "/bundle/gems/ruby2js"
      require "ruby2js"
    `);
    console.log('Ruby2JS loaded!');
    console.log(`  Time: ${((performance.now() - startTime) / 1000).toFixed(2)}s`);

    // Test conversion
    console.log('\n=== Step 3: Test Conversion ===');
    const testCases = [
      'puts "Hello from Ruby2JS!"',
      'x = [1, 2, 3].map { |n| n * 2 }',
      'class Foo; def bar; @x = 1; end; end',
    ];

    for (const ruby of testCases) {
      const js = vm.eval(`Ruby2JS.convert(${JSON.stringify(ruby)}).to_s`).toString();
      console.log(`\nRuby: ${ruby}`);
      console.log(`JS:   ${js}`);
    }

    console.log(`\n=== Complete: ${((performance.now() - startTime) / 1000).toFixed(2)}s ===`);

  } catch (error) {
    console.error('Error:', error.message);
    console.error(error.stack);
    process.exit(1);
  }
}

main();
