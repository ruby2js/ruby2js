// Node.js proof of concept for Ruby2JS with Ruby 4.0 + Prism
const fs = require('fs');
const { WASI } = require('wasi');
const { RubyVM } = require('@ruby/wasm-wasi');

const wasmFile = process.argv[2] || './ruby2js-4.0.wasm';

console.log(`Loading ${wasmFile}...`);
const startTime = performance.now();

async function main() {
  const wasmBuffer = fs.readFileSync(wasmFile);
  console.log(`  File read: ${((performance.now() - startTime) / 1000).toFixed(2)}s (${(wasmBuffer.length / 1024 / 1024).toFixed(1)} MB)`);

  const module = await WebAssembly.compile(wasmBuffer);
  console.log(`  WASM compiled: ${((performance.now() - startTime) / 1000).toFixed(2)}s`);

  const wasi = new WASI({ version: 'preview1' });
  const vm = new RubyVM();
  const imports = { wasi_snapshot_preview1: wasi.wasiImport };
  vm.addToImports(imports);
  const instance = await WebAssembly.instantiate(module, imports);
  await vm.setInstance(instance);
  wasi.initialize(instance);
  vm.initialize();
  console.log(`  Ruby VM initialized: ${((performance.now() - startTime) / 1000).toFixed(2)}s`);

  console.log('\n=== Ruby Environment ===');
  console.log('Ruby version:', vm.eval('RUBY_VERSION').toString());
  console.log('Prism version:', vm.eval('require "prism"; Prism::VERSION').toString());

  // Setup require monkey-patch for packed gems
  vm.eval(`
    $VERBOSE = nil  # Suppress warnings about constant redefinitions
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
  console.log(`  Ruby2JS loaded: ${((performance.now() - startTime) / 1000).toFixed(2)}s`);
  console.log('Parser:', vm.eval('RUBY2JS_PARSER').toString());

  console.log('\n=== Test Conversions ===');
  const testCases = [
    'puts "Hello from Ruby 4.0!"',
    'x = [1, 2, 3].map { |n| n * 2 }',
    'class Foo; def bar; @x = 1; end; end',
    '[1, 2, 3].map { _1 * 2 }',  // Ruby numbered params
  ];

  for (const ruby of testCases) {
    const js = vm.eval(`Ruby2JS.convert(${JSON.stringify(ruby)}).to_s`).toString();
    console.log(`\nRuby: ${ruby}`);
    console.log(`JS:   ${js}`);
  }

  console.log(`\n=== Complete: ${((performance.now() - startTime) / 1000).toFixed(2)}s ===`);
}

main().catch(e => {
  console.error('Error:', e.message);
  process.exit(1);
});
