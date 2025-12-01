// Test the transpiled PrismWalker with @ruby/prism
import { loadPrism } from "@ruby/prism";
import { Node, s, PrismWalker } from "./transpiled_walker.mjs";
import { describe, it, printResults } from "./test_harness.mjs";

const parse = await loadPrism();

// Create a walker instance
const walker = new PrismWalker("");

// Helper to parse Ruby and get AST
function parseRuby(code) {
  const result = parse(code);
  return walker.visit(result.value);
}

// Helper to get AST type
function astType(code) {
  const ast = parseRuby(code);
  return ast?.type;
}

// Helper to get AST as simple string representation
function astStr(node) {
  if (!node) return "nil";
  if (node.children.length === 0) return `(${node.type})`;
  const children = node.children.map(c => {
    if (c instanceof Node) return astStr(c);
    if (typeof c === "string") return `"${c}"`;
    return String(c);
  }).join(" ");
  return `(${node.type} ${children})`;
}

describe("transpiled walker - literals", () => {
  it("should parse integers", () => {
    astType("42").must_equal("int");
    astStr(parseRuby("42")).must_equal("(int 42)");
  });

  it("should parse floats", () => {
    astType("3.14").must_equal("float");
  });

  it("should parse nil", () => {
    astType("nil").must_equal("nil");
  });

  it("should parse booleans", () => {
    astType("true").must_equal("true");
    astType("false").must_equal("false");
  });

  it("should parse strings", () => {
    astType('"hello"').must_equal("str");
    astStr(parseRuby('"hello"')).must_equal('(str "hello")');
  });
});

describe("transpiled walker - variables", () => {
  it("should parse local variable read", () => {
    // In a program context, bare identifier is a method call not lvar
    // Let's test assignment which creates an lvar
    const ast = parseRuby("x = 1");
    ast.type.must_equal("lvasgn");
  });

  it("should parse instance variable read", () => {
    const ast = parseRuby("@foo");
    ast.type.must_equal("ivar");
  });

  it("should parse instance variable write", () => {
    const ast = parseRuby("@foo = 1");
    ast.type.must_equal("ivasgn");
  });
});

describe("transpiled walker - collections", () => {
  it("should parse arrays", () => {
    const ast = parseRuby("[1, 2, 3]");
    ast.type.must_equal("array");
    String(ast.children.length).must_equal("3");
  });

  it("should parse hashes", () => {
    const ast = parseRuby("{a: 1, b: 2}");
    ast.type.must_equal("hash");
    String(ast.children.length).must_equal("2");
  });
});

describe("transpiled walker - method calls", () => {
  it("should parse method call with receiver", () => {
    const ast = parseRuby("foo.bar(1)");
    ast.type.must_equal("send");
    // children: [receiver, method_name, ...args]
    ast.children[1].must_equal("bar");
  });

  it("should parse method call without receiver", () => {
    const ast = parseRuby("puts(1)");
    ast.type.must_equal("send");
    String(ast.children[0] === null).must_equal("true");
    ast.children[1].must_equal("puts");
  });
});

describe("transpiled walker - definitions", () => {
  it("should parse method definition", () => {
    const ast = parseRuby("def greet(name); name; end");
    ast.type.must_equal("def");
    ast.children[0].must_equal("greet"); // method name
    ast.children[1].type.must_equal("args"); // args node
  });
});

describe("transpiled walker - control flow", () => {
  it("should parse if statement", () => {
    const ast = parseRuby("if true; 1; end");
    ast.type.must_equal("if");
  });
});

// Run and report
const success = printResults();
process.exit(success ? 0 : 1);
