// Debug why case/switch doesn't get blank line before default
import { initPrism } from './test_harness.mjs';
await initPrism();

const { Ruby2JS: ConverterModule } = await import('./dist/converter.mjs');
const { Ruby2JS: WalkerModule } = await import('./dist/walker.mjs');

const { Converter, Serializer, Line, Token } = ConverterModule;

// Test case: switch with case and default
const source = `case 1
when 1
a()
else
b()
end`;

// Parse
const Prism = globalThis.Prism;
const prismParse = await Prism.loadPrism();
const parseResult = prismParse(source);

// Walk
const walker = new WalkerModule.PrismWalker(source, null);
const ast = walker.visit(parseResult.value);

console.log("AST:");
console.log(JSON.stringify(ast, null, 2));

// Convert
const converter = new Converter(ast, {}, {});
converter.namespace = new globalThis.Namespace();
// Enable vertical whitespace since we have a multiline test
converter.enable_vertical_whitespace;
converter.convert;

// Inspect lines BEFORE respace
console.log("\nLines before respace:");
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
console.log(JSON.stringify("switch (1) {\ncase 1:\n  a();\n  break;\n\ndefault:\n  b()\n}"));
