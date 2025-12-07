// Ruby2JS selfhosted converter using @ruby/prism parser
// TDD: incrementally add features as tests require them

import { loadPrism } from "@ruby/prism";
import { PrismWalker, Converter } from './dist/walker.mjs';

// Load prism parser immediately on module load
const parse = await loadPrism();

class Ruby2JS {
  static convert(code, options = {}) {
    const result = parse(code);

    // Check for parse errors
    if (result.errors && result.errors.length > 0) {
      throw new Error(`Parse error: ${result.errors[0].message}`);
    }

    const walker = new PrismWalker(code);
    const ast = walker.visit(result.value);

    const converter = new Converter(options);
    const js = converter.convert(ast);

    return {
      toString() {
        return js;
      }
    };
  }
}

export default Ruby2JS;
