// Test the full Ruby → JavaScript pipeline
// Ruby source → @ruby/prism → PrismWalker → Converter → JavaScript output

import { loadPrism } from "@ruby/prism";
import { Node, s, PrismWalker, Converter } from "./transpiled_walker.mjs";
import { describe, it, printResults } from "./test_harness.mjs";

const parse = await loadPrism();

// Full conversion function
function convert(rubyCode) {
  const result = parse(rubyCode);
  const walker = new PrismWalker(rubyCode);
  const ast = walker.visit(result.value);
  const converter = new Converter();
  return converter.convert(ast);
}

describe("full pipeline - literals", () => {
  it("should convert integers", () => {
    convert("42").must_equal("42");
  });

  it("should convert floats", () => {
    convert("3.14").must_equal("3.14");
  });

  it("should convert strings", () => {
    convert('"hello"').must_equal('"hello"');
  });

  it("should convert nil", () => {
    convert("nil").must_equal("null");
  });

  it("should convert booleans", () => {
    convert("true").must_equal("true");
    convert("false").must_equal("false");
  });
});

describe("full pipeline - variables", () => {
  it("should convert local variable assignment", () => {
    convert("x = 1").must_equal("let x = 1");
  });

  it("should convert instance variable assignment", () => {
    convert("@foo = 1").must_equal("this._foo = 1");
  });
});

describe("full pipeline - collections", () => {
  it("should convert arrays", () => {
    convert("[1, 2, 3]").must_equal("[1, 2, 3]");
  });

  it("should convert hashes", () => {
    convert("{a: 1, b: 2}").must_equal('{"a": 1, "b": 2}');
  });
});

describe("full pipeline - method calls", () => {
  it("should convert puts to console.log", () => {
    convert('puts "hello"').must_equal('console.log("hello")');
  });

  it("should convert method calls on objects", () => {
    // In Ruby, `foo` without prior assignment is a method call, not a variable
    // So foo.bar(1, 2) becomes foo().bar(1, 2)
    convert("foo.bar(1, 2)").must_equal("foo().bar(1, 2)");
  });

  it("should convert method calls on variables", () => {
    // When foo is assigned first, it's a variable
    convert("foo = obj; foo.bar(1)").must_include("foo.bar(1)");
  });
});

describe("full pipeline - definitions", () => {
  it("should convert method definitions", () => {
    const result = convert("def greet(name); name; end");
    result.must_include("function greet(name)");
    result.must_include("return name");
  });
});

// Run and report
const success = printResults();
process.exit(success ? 0 : 1);
