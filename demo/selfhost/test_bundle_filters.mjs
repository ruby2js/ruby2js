import { convert, Ruby2JS } from './ruby2js.mjs';
import Functions from './dist/functions_filter.mjs';

// Try using bundle's convert directly with a filter
console.log("Testing bundle convert with filter:");
try {
  const result = convert("[1,2,3].first", {
    eslevel: 2022,
    filters: [Functions]
  });
  console.log("Result:", result);
} catch (e) {
  console.log("Error:", e.message);
  console.log(e.stack);
}
