// Debug why converter produces extra blank lines
import { Ruby2JS, initPrism, getPrismParse } from './ruby2js.js';
await initPrism();

const { Converter, Serializer, Line, Token, PrismWalker } = Ruby2JS;

// Test case: multi-statement block with newlines (like actual test)
const source = "if true\na()\nb()\nend";

// Parse
const prismParse = getPrismParse();
const parseResult = prismParse(source);

// Walk
const walker = new PrismWalker(source, null);
const ast = walker.visit(parseResult.value);

// Convert
const converter = new Converter(ast, {}, {});
converter.namespace = new Ruby2JS.Namespace();
// Enable vertical whitespace since we have a multiline test
converter.enable_vertical_whitespace;
converter.convert;

// Inspect lines BEFORE respace
console.log("Lines before respace:");
converter._lines.forEach((line, i) => {
  const tokens = line._tokens?.map(t => t._string || t.toString()) || [];
  console.log(`  [${i}] indent=${line.indent}, tokens=${JSON.stringify(tokens)}`);
});

// Now trigger respace via to_s
const result = converter.to_s;

console.log("\nLines after respace:");
converter._lines.forEach((line, i) => {
  const tokens = line._tokens?.map(t => t._string || t.toString()) || [];
  console.log(`  [${i}] indent=${line.indent}, tokens=${JSON.stringify(tokens)}`);
});

console.log("\nFinal output:");
console.log(JSON.stringify(result));

console.log("\nExpected:");
console.log(JSON.stringify("if (true) {a(); b()}"));
