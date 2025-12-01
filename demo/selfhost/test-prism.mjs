// Test @ruby/prism AST structure
import { loadPrism } from "@ruby/prism";

const parse = await loadPrism();

// Test simple expressions
const tests = [
  '1',
  '"hello"',
  ':symbol',
  'foo',
  'foo = 1',
  '@foo',
  'foo + bar',
  'foo.bar(1, 2)',
  'def greet(name); puts name; end',
  '[1, 2, 3]',
  '{a: 1, b: 2}',
];

for (const code of tests) {
  console.log(`\n${'='.repeat(60)}`);
  console.log(`Ruby: ${code}`);
  console.log('='.repeat(60));

  const result = parse(code);
  const ast = result.value;

  // Print the AST structure
  console.log(JSON.stringify(ast, (key, value) => {
    // Skip location info for readability
    if (key === 'location' || key === 'startOffset' || key === 'endOffset') {
      return undefined;
    }
    // Show node type
    if (value && typeof value === 'object' && value.constructor) {
      return { _type: value.constructor.name, ...value };
    }
    return value;
  }, 2));
}
