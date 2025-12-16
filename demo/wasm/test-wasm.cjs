// Node.js test script for Ruby2JS WASM build
// Uses the same approach as poc-ruby4.html with monkey-patched require
const fs = require('fs');
const { WASI } = require('wasi');
const { RubyVM } = require('@ruby/wasm-wasi');

const wasmFile = process.argv[2] || './ruby2js.wasm';

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

    // Load Ruby2JS with monkey-patched require (workaround for WASI VFS realpath issue)
    console.log('\n=== Step 2: Load Ruby2JS ===');
    vm.eval(`
      $VERBOSE = nil  # Suppress warnings
      def gem(*args); end

      $PACKED_PATHS = ['/gems/ruby2js', '/gems/parser/lib', '/gems/racc/lib', '/gems/ast/lib']
      $LOADED_PACKED = {}

      module Kernel
        alias :original_require :require
        alias :original_require_relative :require_relative

        def require(name)
          name = name.sub(/\\.rb$/, '')
          return false if $LOADED_PACKED[name]

          $PACKED_PATHS.each do |base|
            path = "#{base}/#{name}.rb"
            if File.exist?(path)
              $LOADED_PACKED[name] = true
              eval(File.read(path), TOPLEVEL_BINDING, path)
              return true
            end
          end

          original_require(name)
        end

        def require_relative(name)
          caller_path = caller_locations(1, 1).first.path
          dir = File.dirname(caller_path)
          full_path = File.join(dir, name + '.rb')

          return false if $LOADED_PACKED[full_path]

          if File.exist?(full_path)
            $LOADED_PACKED[full_path] = true
            eval(File.read(full_path), TOPLEVEL_BINDING, full_path)
            return true
          end

          original_require_relative(name)
        end
      end

      ENV['RUBY2JS_PARSER'] = 'prism'
      require 'ruby2js'
    `);

    const parser = vm.eval('RUBY2JS_PARSER rescue "unknown"').toString();
    console.log(`Ruby2JS loaded! Parser: ${parser}`);
    console.log(`  Time: ${((performance.now() - startTime) / 1000).toFixed(2)}s`);

    // Test conversion
    console.log('\n=== Step 3: Test Conversion ===');
    const testCases = [
      'puts "Hello from Ruby2JS!"',
      'x = [1, 2, 3].map { |n| n * 2 }',
      'class Foo; def bar; @x = 1; end; end',
      '[1, 2, 3].map { _1 * 2 }',
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
