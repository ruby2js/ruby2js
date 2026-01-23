// Test the ErbToJsx JavaScript converter

import { initPrism } from './ruby2js.js';
import { ErbToJsx } from './dist/erb_to_jsx.mjs';

await initPrism();

const tests = {
  simple_output: {
    input: '<p><%= article.title %></p>',
    expected: /<p>\{article\.title\}<\/p>/
  },
  simple_if: {
    input: '<% if loading %><p>Loading...</p><% end %>',
    expected: /\{\(loading\) && \(<p>Loading\.\.\.<\/p>\)\}/
  },
  if_else: {
    input: '<% if loading %><p>Loading</p><% else %><p>Done</p><% end %>',
    expected: /\{\(loading\) \? \(<p>Loading<\/p>\) : \(<p>Done<\/p>\)\}/
  },
  unless: {
    input: '<% unless loading %><p>Ready</p><% end %>',
    expected: /\{!\(loading\) && \(<p>Ready<\/p>\)\}/
  },
  each: {
    input: '<% items.each do |item| %><p><%= item.name %></p><% end %>',
    expected: /\{items\.map\(item => \(<p>\{item\.name\}<\/p>\)\)\}/
  },
  class_to_classname: {
    input: '<p class="meta">Text</p>',
    expected: /<p className="meta">Text<\/p>/
  },
  attr_expr: {
    input: '<a href={"/articles/" + id}>Link</a>',
    expected: /<a href=\{"\/articles\/" \+ id\}>Link<\/a>/
  },
  style_object: {
    input: '<div style={{margin: 0}}>X</div>',
    expected: /<div style=\{\{margin: 0\}\}>X<\/div>/
  },
  lambda_attr: {
    input: '<button onClick={-> { handleClick() }}>Click</button>',
    expected: /<button onClick=\{.*handleClick.*\}>Click<\/button>/
  }
};

console.log('Testing ErbToJsx JavaScript converter');
console.log('='.repeat(50));

let passed = 0;
let failed = 0;

for (const [name, test] of Object.entries(tests)) {
  try {
    const result = ErbToJsx.convert(test.input);

    if (test.expected.test(result)) {
      console.log(`✓ ${name}`);
      passed++;
    } else {
      console.log(`✗ ${name}`);
      console.log(`  Input:    ${JSON.stringify(test.input)}`);
      console.log(`  Output:   ${JSON.stringify(result)}`);
      console.log(`  Expected: ${test.expected}`);
      failed++;
    }
  } catch (e) {
    console.log(`✗ ${name} (ERROR)`);
    console.log(`  Input: ${JSON.stringify(test.input)}`);
    console.log(`  Error: ${e.message}`);
    failed++;
  }
}

console.log('='.repeat(50));
console.log(`Results: ${passed} passed, ${failed} failed`);

process.exit(failed > 0 ? 1 : 0);
