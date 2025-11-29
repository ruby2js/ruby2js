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

describe("full pipeline - operators", () => {
  it("should convert arithmetic operators", () => {
    convert("1 + 2").must_equal("(1 + 2)");
    convert("5 - 3").must_equal("(5 - 3)");
    convert("2 * 3").must_equal("(2 * 3)");
    convert("10 / 2").must_equal("(10 / 2)");
    convert("10 % 3").must_equal("(10 % 3)");
  });

  it("should convert comparison operators", () => {
    convert("1 == 2").must_equal("(1 === 2)");
    convert("1 != 2").must_equal("(1 !== 2)");
    convert("1 < 2").must_equal("(1 < 2)");
    convert("1 > 2").must_equal("(1 > 2)");
    convert("1 <= 2").must_equal("(1 <= 2)");
    convert("1 >= 2").must_equal("(1 >= 2)");
  });

  it("should convert logical operators", () => {
    convert("x = true; y = false; x && y").must_include("&& y");
    convert("x = true; y = false; x || y").must_include("|| y");
  });

  it("should convert unary operators", () => {
    convert("x = true; !x").must_include("!x");
  });

  it("should convert array access", () => {
    convert("a = [1, 2, 3]; a[0]").must_include("a[0]");
  });
});

describe("full pipeline - control flow", () => {
  it("should convert while loops", () => {
    const result = convert("x = 0; while x < 10; x = x + 1; end");
    result.must_include("while");
    result.must_include("< 10");
  });

  it("should convert until loops", () => {
    const result = convert("x = 0; until x >= 10; x = x + 1; end");
    result.must_include("while (!");
  });

  it("should convert for loops", () => {
    const result = convert("for i in items; puts i; end");
    result.must_include("for (let");
    result.must_include("of");
  });

  it("should convert case/when", () => {
    const result = convert("case x; when 1; a; when 2; b; else c; end");
    result.must_include("switch");
    result.must_include("case 1");
    result.must_include("case 2");
    result.must_include("default");
  });

  it("should convert return", () => {
    convert("return 42").must_include("return 42");
  });

  it("should convert break", () => {
    convert("break").must_equal("break");
  });
});

describe("full pipeline - string interpolation", () => {
  it("should convert interpolated strings to template literals", () => {
    const result = convert('name = "world"; "hello #{name}"');
    result.must_include("`hello ${name}`");
  });

  it("should handle expressions in interpolation", () => {
    const result = convert('"sum is #{1 + 2}"');
    result.must_include("`sum is ${");
  });
});

describe("full pipeline - ranges", () => {
  it("should convert inclusive ranges", () => {
    const result = convert("1..5");
    result.must_include("Array.from");
    result.must_include("+ 1");  // inclusive adds 1 to length
  });

  it("should convert exclusive ranges", () => {
    const result = convert("1...5");
    result.must_include("Array.from");
  });
});

// Run and report
const success = printResults();
process.exit(success ? 0 : 1);
