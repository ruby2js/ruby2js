// Run transpiled tests against proof-of-concept converter
import { loadPrism } from "@ruby/prism";
import { PrismWalker, Converter } from "./walker.mjs";
import { describe, it, printResults } from "./test_harness.mjs";

const parse = await loadPrism();

// Ruby2JS-like convert function
function convert(rubyCode, opts = {}) {
  const result = parse(rubyCode);
  const walker = new PrismWalker(rubyCode);
  const ast = walker.visit(result.value);
  const converter = new Converter();
  return converter.convert(ast);
}

// Helper matching the Ruby spec's to_js
function to_js(string, opts = {}) {
  return convert(string, { ...opts, filters: [] });
}

// Transpiled tests (would be generated from Ruby specs)
describe("literals", () => {
  it("should parse integers", () => {
    to_js("1").must_equal("1");
    to_js("42").must_equal("42");
  });

  it("should parse strings", () => {
    to_js('"hello"').must_equal('"hello"');
  });

  it("should parse nil", () => {
    to_js("nil").must_equal("null");
  });

  it("should parse booleans", () => {
    to_js("true").must_equal("true");
    to_js("false").must_equal("false");
  });

  it("should parse arrays", () => {
    to_js("[1, 2, 3]").must_equal("[1, 2, 3]");
  });

  it("should parse hashes", () => {
    to_js("{a: 1, b: 2}").must_equal("{a: 1, b: 2}");
  });
});

describe("variables", () => {
  it("should parse local variable assignment", () => {
    to_js("foo = 1").must_equal("let foo = 1");
  });

  it("should parse instance variable assignment", () => {
    to_js("@foo = 1").must_equal("this._foo = 1");
  });
});

describe("method calls", () => {
  it("should convert puts to console.log", () => {
    to_js('puts "hello"').must_equal('console.log("hello")');
  });

  it("should handle method calls with arguments", () => {
    to_js("foo.bar(1, 2)").must_equal("foo.bar(1, 2)");
  });
});

describe("method definitions", () => {
  it("should convert def to function", () => {
    to_js("def greet(name); puts name; end").must_equal(
      "function greet(name) {\n  return console.log(name);\n}"
    );
  });
});

// Run and report
const success = printResults();
process.exit(success ? 0 : 1);
